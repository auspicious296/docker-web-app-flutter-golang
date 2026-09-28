package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"backend/internal/model"
	"backend/internal/repository"
	"backend/internal/service"
)

// handler 層のテストは DB を使わない。service を、手書きのフェイクの repository で
// 組み立てて使う（ADR 0003 のテストの方針と同じ）。

// ---- フェイク ----

type fakeUsers struct{ users []model.User }

func (f *fakeUsers) find(id int64) int {
	for i, u := range f.users {
		if u.ID == id && u.DeletedAt == nil {
			return i
		}
	}
	return -1
}

func (f *fakeUsers) FindByID(_ context.Context, id int64, _ bool) (model.User, error) {
	if i := f.find(id); i >= 0 {
		return f.users[i], nil
	}
	return model.User{}, repository.ErrNotFound
}

func (f *fakeUsers) FindActiveByEmail(_ context.Context, email string) (model.User, error) {
	for _, u := range f.users {
		if u.Email == email && u.DeletedAt == nil {
			return u, nil
		}
	}
	return model.User{}, repository.ErrNotFound
}

func (f *fakeUsers) RecordLoginFailure(_ context.Context, id int64, maxAttempts int) (bool, error) {
	i := f.find(id)
	if i < 0 || f.users[i].IsLocked {
		return false, repository.ErrNotFound
	}
	f.users[i].FailedLoginAttempts++
	f.users[i].IsLocked = f.users[i].FailedLoginAttempts >= maxAttempts
	return f.users[i].IsLocked, nil
}

func (f *fakeUsers) ResetLoginFailures(_ context.Context, id int64) error {
	if i := f.find(id); i >= 0 {
		f.users[i].FailedLoginAttempts = 0
	}
	return nil
}

func (f *fakeUsers) RecordLoginSuccess(_ context.Context, id int64) error {
	if i := f.find(id); i >= 0 {
		now := time.Now()
		f.users[i].FailedLoginAttempts = 0
		f.users[i].LastLoginAt = &now
	}
	return nil
}

func (f *fakeUsers) UpdatePassword(_ context.Context, id int64, hash string, _ []byte) (model.User, error) {
	i := f.find(id)
	if i < 0 {
		return model.User{}, repository.ErrNotFound
	}
	f.users[i].PasswordHash = hash
	return f.users[i], nil
}

type fakeSessions struct{ m map[string]model.Session }

func (f *fakeSessions) Create(_ context.Context, idHash []byte, userID int64, clientType, csrfToken string) error {
	f.m[string(idHash)] = model.Session{IDHash: idHash, UserID: userID, ClientType: clientType, CSRFToken: csrfToken}
	return nil
}

func (f *fakeSessions) Touch(_ context.Context, idHash []byte, _ model.SessionTimeouts) (model.Session, error) {
	if s, ok := f.m[string(idHash)]; ok {
		return s, nil
	}
	return model.Session{}, repository.ErrNotFound
}

func (f *fakeSessions) Delete(_ context.Context, idHash []byte) error {
	delete(f.m, string(idHash))
	return nil
}

func (f *fakeSessions) DeleteExpired(context.Context, model.SessionTimeouts) (int64, error) {
	return 0, nil
}

// ---- 共通の準備 ----

const (
	origin       = "https://myapp.local"
	testEmail    = "taro@example.com"
	testPassword = "password123"
)

type testEnv struct {
	handler  http.Handler
	users    *fakeUsers
	sessions *fakeSessions
}

func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	hash, err := bcrypt.GenerateFromPassword([]byte(testPassword), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	users := &fakeUsers{users: []model.User{{ID: 1, Name: "山田 太郎", Email: testEmail, PasswordHash: string(hash)}}}
	sessions := &fakeSessions{m: map[string]model.Session{}}

	svc, err := service.NewAuthService(users, sessions, service.AuthConfig{
		BcryptCost:     bcrypt.MinCost,
		Timeouts:       model.SessionTimeouts{WebIdle: time.Hour, WebAbsolute: time.Hour, MobileIdle: time.Hour, MobileAbsolute: time.Hour},
		CSRFSigningKey: []byte("test-signing-key"),
	})
	if err != nil {
		t.Fatal(err)
	}

	mux := http.NewServeMux()
	NewAuthHandler(svc, origin).Register(mux)
	return &testEnv{handler: JSONErrorFallback(mux), users: users, sessions: sessions}
}

// reqOption はリクエストにヘッダーや Cookie を付ける。
type reqOption func(*http.Request)

func withOrigin(o string) reqOption { return func(r *http.Request) { r.Header.Set("Origin", o) } }
func withCSRF(token string) reqOption {
	return func(r *http.Request) { r.Header.Set(csrfHeaderName, token) }
}
func withCookie(name, value string) reqOption {
	return func(r *http.Request) { r.AddCookie(&http.Cookie{Name: name, Value: value}) }
}
func withBearer(id string) reqOption {
	return func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+id) }
}

func (e *testEnv) do(method, path, body string, opts ...reqOption) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	for _, o := range opts {
		o(req)
	}
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	return rec
}

// responseCookie は、レスポンスで発行された Cookie を返す。
func responseCookie(t *testing.T, rec *httptest.ResponseRecorder, name string) *http.Cookie {
	t.Helper()
	for _, c := range rec.Result().Cookies() {
		if c.Name == name {
			return c
		}
	}
	t.Fatalf("Cookie %s が発行されていない", name)
	return nil
}

type errorBodyForTest struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
		Fields  []struct {
			Field   string `json:"field"`
			Message string `json:"message"`
		} `json:"fields"`
	} `json:"error"`
}

// assertError は、ステータスコードとエラーコードを確かめる。
func assertError(t *testing.T, rec *httptest.ResponseRecorder, status int, code string) errorBodyForTest {
	t.Helper()
	var body errorBodyForTest
	if rec.Code != status {
		t.Fatalf("ステータスコード %d を期待したが %d: %s", status, rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("本文が JSON ではない: %s", rec.Body.String())
	}
	if body.Error.Code != code {
		t.Fatalf("エラーコード %s を期待したが %s", code, body.Error.Code)
	}
	return body
}

// preLoginCSRF は、ログイン前の CSRF トークンと、その署名付き Cookie の値を受け取る。
func (e *testEnv) preLoginCSRF(t *testing.T) (token, cookie string) {
	t.Helper()
	rec := e.do("GET", "/api/csrf-token", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("CSRF トークンを受け取れない: %d", rec.Code)
	}
	var body struct {
		CSRFToken string `json:"csrf_token"`
	}
	json.Unmarshal(rec.Body.Bytes(), &body)
	return body.CSRFToken, responseCookie(t, rec, preLoginCSRFCookieName).Value
}

// webLogin は Web 用のログインを行い、セッション ID を返す。
func (e *testEnv) webLogin(t *testing.T) string {
	t.Helper()
	token, cookie := e.preLoginCSRF(t)
	rec := e.do("POST", "/api/login", `{"email":"`+testEmail+`","password":"`+testPassword+`"}`,
		withOrigin(origin), withCookie(preLoginCSRFCookieName, cookie), withCSRF(token))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("Web 用のログインに失敗した: %d %s", rec.Code, rec.Body.String())
	}
	return responseCookie(t, rec, sessionCookieName).Value
}

// sessionCSRF は、ログイン後の CSRF トークンを受け取る。
func (e *testEnv) sessionCSRF(t *testing.T, sessionID string) string {
	t.Helper()
	rec := e.do("GET", "/api/csrf-token", "", withCookie(sessionCookieName, sessionID))
	var body struct {
		CSRFToken string `json:"csrf_token"`
	}
	json.Unmarshal(rec.Body.Bytes(), &body)
	return body.CSRFToken
}

// ---- CSRF トークンの発行 ----

func TestCSRFTokenBeforeLogin(t *testing.T) {
	e := newTestEnv(t)
	rec := e.do("GET", "/api/csrf-token", "")

	if rec.Code != http.StatusOK || rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("200 と Cache-Control: no-store を返す: %d %q", rec.Code, rec.Header().Get("Cache-Control"))
	}
	c := responseCookie(t, rec, preLoginCSRFCookieName)
	if !c.HttpOnly || !c.Secure || c.SameSite != http.SameSiteStrictMode || c.Path != "/" || c.MaxAge != 0 {
		t.Errorf("Cookie の属性が ADR 0012 と異なる: %+v", c)
	}
}

func TestCSRFTokenAfterLoginReturnsSessionToken(t *testing.T) {
	e := newTestEnv(t)
	id := e.webLogin(t)

	token := e.sessionCSRF(t, id)
	var stored string
	for _, s := range e.sessions.m {
		stored = s.CSRFToken
	}
	if token == "" || token != stored {
		t.Errorf("ログイン中は、今のセッションのトークンを返す: %q / %q", token, stored)
	}
}

// ---- Web 用のログイン ----

func TestWebLoginSucceeds(t *testing.T) {
	e := newTestEnv(t)
	token, cookie := e.preLoginCSRF(t)
	rec := e.do("POST", "/api/login", `{"email":"`+testEmail+`","password":"`+testPassword+`"}`,
		withOrigin(origin), withCookie(preLoginCSRFCookieName, cookie), withCSRF(token))

	if rec.Code != http.StatusNoContent || rec.Body.Len() != 0 {
		t.Fatalf("204 と空の本文を返す: %d %q", rec.Code, rec.Body.String())
	}
	s := responseCookie(t, rec, sessionCookieName)
	if !s.HttpOnly || !s.Secure || s.SameSite != http.SameSiteStrictMode || s.Path != "/" || s.MaxAge != 0 {
		t.Errorf("セッションの Cookie の属性が ADR 0012・0013 と異なる: %+v", s)
	}
	if c := responseCookie(t, rec, preLoginCSRFCookieName); c.MaxAge >= 0 {
		t.Errorf("ログイン前の CSRF トークンの Cookie を消させる: %+v", c)
	}
}

func TestWebLoginRejectsOrigin(t *testing.T) {
	e := newTestEnv(t)
	token, cookie := e.preLoginCSRF(t)
	body := `{"email":"` + testEmail + `","password":"` + testPassword + `"}`

	for name, opts := range map[string][]reqOption{
		"Origin がない":   {withCookie(preLoginCSRFCookieName, cookie), withCSRF(token)},
		"Origin が異なる":  {withOrigin("https://evil.example"), withCookie(preLoginCSRFCookieName, cookie), withCSRF(token)},
		"CSRF トークンがない": {withOrigin(origin), withCookie(preLoginCSRFCookieName, cookie)},
	} {
		code := "origin_not_allowed"
		if name == "CSRF トークンがない" {
			code = "csrf_token_invalid"
		}
		t.Run(name, func(t *testing.T) {
			assertError(t, e.do("POST", "/api/login", body, opts...), http.StatusForbidden, code)
		})
	}
}

func TestWebLoginFailures(t *testing.T) {
	e := newTestEnv(t)
	login := func(body string) *httptest.ResponseRecorder {
		token, cookie := e.preLoginCSRF(t)
		return e.do("POST", "/api/login", body, withOrigin(origin), withCookie(preLoginCSRFCookieName, cookie), withCSRF(token))
	}

	body := assertError(t, login(`{"email":"","password":""}`), http.StatusBadRequest, "validation_error")
	if len(body.Error.Fields) != 2 {
		t.Errorf("email と password の 2 項目を返す: %+v", body.Error.Fields)
	}

	body = assertError(t, login(`{"email":"`+testEmail+`","password":"wrong-password"}`), http.StatusUnauthorized, "invalid_credentials")
	if body.Error.Message != "メールアドレスまたはパスワードが正しくありません。" {
		t.Errorf("メッセージが ADR 0014 と異なる: %s", body.Error.Message)
	}
	assertError(t, login(`{"email":"unknown@example.com","password":"`+testPassword+`"}`), http.StatusUnauthorized, "invalid_credentials")

	e.users.users[0].IsLocked = true
	body = assertError(t, login(`{"email":"`+testEmail+`","password":"`+testPassword+`"}`), http.StatusForbidden, "account_locked")
	if body.Error.Message != "アカウントがロックされています。管理者に解除を依頼してください。" {
		t.Errorf("メッセージが ADR 0014 と異なる: %s", body.Error.Message)
	}
}

// ---- モバイル用のログイン ----

func TestMobileLogin(t *testing.T) {
	e := newTestEnv(t)
	body := `{"email":"` + testEmail + `","password":"` + testPassword + `"}`

	rec := e.do("POST", "/api/mobile/login", body)
	if rec.Code != http.StatusOK {
		t.Fatalf("200 を返す: %d %s", rec.Code, rec.Body.String())
	}
	var got map[string]string
	json.Unmarshal(rec.Body.Bytes(), &got)
	if len(got) != 1 || got["session_id"] == "" {
		t.Errorf(`本文は {"session_id":"..."} だけ: %s`, rec.Body.String())
	}
	if len(rec.Result().Cookies()) != 0 {
		t.Error("モバイル用のログインでは Cookie を発行しない")
	}

	// Origin が付いていたら、ブラウザからの誤った呼び出しとして拒否する。
	assertError(t, e.do("POST", "/api/mobile/login", body, withOrigin(origin)), http.StatusForbidden, "origin_not_allowed")
}

// ---- ログインが必要な API ----

func TestMe(t *testing.T) {
	e := newTestEnv(t)
	assertError(t, e.do("GET", "/api/me", ""), http.StatusUnauthorized, "unauthenticated")
	assertError(t, e.do("GET", "/api/me", "", withBearer("unknown")), http.StatusUnauthorized, "unauthenticated")

	id := e.webLogin(t)
	// GET は CSRF トークンと Origin の判定の対象外。
	rec := e.do("GET", "/api/me", "", withCookie(sessionCookieName, id))
	if rec.Code != http.StatusOK {
		t.Fatalf("200 を返す: %d %s", rec.Code, rec.Body.String())
	}
	var got map[string]any
	json.Unmarshal(rec.Body.Bytes(), &got)
	if len(got) != 3 || got["id"] != float64(1) || got["name"] != "山田 太郎" || got["email"] != testEmail {
		t.Errorf("id・name・email の 3 項目だけを返す: %s", rec.Body.String())
	}
}

func TestAmbiguousSession(t *testing.T) {
	e := newTestEnv(t)
	id := e.webLogin(t)
	rec := e.do("GET", "/api/me", "", withCookie(sessionCookieName, id), withBearer(id))
	assertError(t, rec, http.StatusBadRequest, "ambiguous_session")
}

func TestChangePasswordWithCookieRequiresOriginAndCSRF(t *testing.T) {
	e := newTestEnv(t)
	id := e.webLogin(t)
	csrf := e.sessionCSRF(t, id)
	body := `{"current_password":"` + testPassword + `","new_password":"new-password456"}`

	assertError(t, e.do("PUT", "/api/me/password", body, withCookie(sessionCookieName, id), withCSRF(csrf)),
		http.StatusForbidden, "origin_not_allowed")
	assertError(t, e.do("PUT", "/api/me/password", body, withCookie(sessionCookieName, id), withOrigin(origin)),
		http.StatusForbidden, "csrf_token_invalid")
	assertError(t, e.do("PUT", "/api/me/password", body, withCookie(sessionCookieName, id), withOrigin(origin), withCSRF("wrong")),
		http.StatusForbidden, "csrf_token_invalid")

	rec := e.do("PUT", "/api/me/password", body, withCookie(sessionCookieName, id), withOrigin(origin), withCSRF(csrf))
	if rec.Code != http.StatusNoContent || rec.Body.Len() != 0 {
		t.Fatalf("204 と空の本文を返す: %d %s", rec.Code, rec.Body.String())
	}
}

func TestChangePasswordWithBearerNeedsNoCSRF(t *testing.T) {
	e := newTestEnv(t)
	rec := e.do("POST", "/api/mobile/login", `{"email":"`+testEmail+`","password":"`+testPassword+`"}`)
	var got map[string]string
	json.Unmarshal(rec.Body.Bytes(), &got)

	body := `{"current_password":"wrong-password","new_password":"new-password456"}`
	res := assertError(t, e.do("PUT", "/api/me/password", body, withBearer(got["session_id"])), http.StatusBadRequest, "validation_error")
	if len(res.Error.Fields) != 1 || res.Error.Fields[0].Field != "current_password" ||
		res.Error.Fields[0].Message != "現在のパスワードが正しくありません" {
		t.Errorf("current_password の誤りを fields で返す: %+v", res.Error.Fields)
	}

	body = `{"current_password":"` + testPassword + `","new_password":"new-password456"}`
	if rec := e.do("PUT", "/api/me/password", body, withBearer(got["session_id"])); rec.Code != http.StatusNoContent {
		t.Fatalf("ヘッダーで送るモバイルは CSRF トークンなしで変更できる: %d %s", rec.Code, rec.Body.String())
	}
}

func TestLogout(t *testing.T) {
	e := newTestEnv(t)
	id := e.webLogin(t)
	csrf := e.sessionCSRF(t, id)

	rec := e.do("POST", "/api/logout", "", withCookie(sessionCookieName, id), withOrigin(origin), withCSRF(csrf))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("204 を返す: %d %s", rec.Code, rec.Body.String())
	}
	if c := responseCookie(t, rec, sessionCookieName); c.MaxAge >= 0 {
		t.Errorf("セッションの Cookie を消させる: %+v", c)
	}

	// ログアウトした後は、ログインが必要な API は 401 になる。ログアウトし直しても
	// 例外は作らず 401（ADR 0014）。
	assertError(t, e.do("GET", "/api/me", "", withCookie(sessionCookieName, id)), http.StatusUnauthorized, "unauthenticated")
	assertError(t, e.do("POST", "/api/logout", "", withCookie(sessionCookieName, id), withOrigin(origin), withCSRF(csrf)),
		http.StatusUnauthorized, "unauthenticated")
}
