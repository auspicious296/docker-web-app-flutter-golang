package service

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"backend/internal/model"
	"backend/internal/repository"
)

// ---- users テーブルのフェイク（AuthUserRepository の分） ----

func (f *fakeUserRepository) FindActiveByEmail(_ context.Context, email string) (model.User, error) {
	for _, u := range f.users {
		if u.Email == email && u.DeletedAt == nil {
			return u, nil
		}
	}
	return model.User{}, repository.ErrNotFound
}

// RecordLoginFailure は、実際の SQL と同じく、ロック中・削除済みなら ErrNotFound を返す。
func (f *fakeUserRepository) RecordLoginFailure(_ context.Context, id int64, maxAttempts int) (bool, error) {
	i := f.index(id, false)
	if i < 0 || f.users[i].IsLocked {
		return false, repository.ErrNotFound
	}
	f.users[i].FailedLoginAttempts++
	if f.users[i].FailedLoginAttempts >= maxAttempts {
		now := fixedTime()
		f.users[i].IsLocked = true
		f.users[i].LockedAt = &now
	}
	return f.users[i].IsLocked, nil
}

func (f *fakeUserRepository) ResetLoginFailures(_ context.Context, id int64) error {
	if i := f.index(id, true); i >= 0 {
		f.users[i].FailedLoginAttempts = 0
	}
	return nil
}

// RecordLoginSuccess は、実際の SQL と同じく、削除済みには何もしない。
func (f *fakeUserRepository) RecordLoginSuccess(_ context.Context, id int64) error {
	if i := f.index(id, false); i >= 0 {
		now := fixedTime()
		f.users[i].FailedLoginAttempts = 0
		f.users[i].LastLoginAt = &now
	}
	return nil
}

// ---- sessions テーブルのフェイク ----

// fakeSessionRepository は SessionRepository の手書きのフェイク。
// タイムアウトの判定は SQL の中で行うため、ここでは扱わない（repository 層のテストで確かめる）。
type fakeSessionRepository struct {
	sessions map[string]model.Session
}

func newFakeSessions() *fakeSessionRepository {
	return &fakeSessionRepository{sessions: map[string]model.Session{}}
}

func (f *fakeSessionRepository) Create(_ context.Context, idHash []byte, userID int64, clientType, csrfToken string) error {
	f.sessions[string(idHash)] = model.Session{
		IDHash: idHash, UserID: userID, ClientType: clientType, CSRFToken: csrfToken,
		CreatedAt: fixedTime(), LastAccessedAt: fixedTime(),
	}
	return nil
}

func (f *fakeSessionRepository) Touch(_ context.Context, idHash []byte, _ model.SessionTimeouts) (model.Session, error) {
	s, ok := f.sessions[string(idHash)]
	if !ok {
		return model.Session{}, repository.ErrNotFound
	}
	return s, nil
}

func (f *fakeSessionRepository) Delete(_ context.Context, idHash []byte) error {
	delete(f.sessions, string(idHash))
	return nil
}

func (f *fakeSessionRepository) DeleteExpired(_ context.Context, _ model.SessionTimeouts) (int64, error) {
	return 0, nil
}

// ---- 共通の準備 ----

const (
	testEmail    = "taro@example.com"
	testPassword = "password123"
)

var testCSRFKey = []byte("test-signing-key")

// hashOf はテスト用に、bcrypt のコストを最小にしてハッシュ値を作る。
func hashOf(t *testing.T, password string) string {
	t.Helper()
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	return string(h)
}

// testUser は、testEmail / testPassword でログインできるユーザーを作る。
func testUser(t *testing.T) model.User {
	t.Helper()
	return model.User{ID: 1, Name: "山田 太郎", Email: testEmail, PasswordHash: hashOf(t, testPassword)}
}

func newAuth(t *testing.T, users *fakeUserRepository, sessions *fakeSessionRepository) *AuthService {
	t.Helper()
	s, err := NewAuthService(users, sessions, AuthConfig{
		BcryptCost:     bcrypt.MinCost,
		Timeouts:       model.SessionTimeouts{WebIdle: time.Hour, WebAbsolute: time.Hour, MobileIdle: time.Hour, MobileAbsolute: time.Hour},
		CSRFSigningKey: testCSRFKey,
	})
	if err != nil {
		t.Fatal(err)
	}
	return s
}

// login は、ログインに成功したことを確かめてセッションを返す。
func login(t *testing.T, auth *AuthService, sessions *fakeSessionRepository) model.Session {
	t.Helper()
	id, err := auth.Login(context.Background(), testEmail, testPassword, model.ClientWeb, "")
	if err != nil {
		t.Fatalf("ログインに失敗した: %v", err)
	}
	s, ok := sessions.sessions[string(hashSessionID(id))]
	if !ok {
		t.Fatal("セッションが保存されていない")
	}
	return s
}

func hasIssue(issues []Issue, field string, reason Reason) bool {
	return slices.Contains(issues, Issue{Field: field, Reason: reason})
}

// ---- ログイン ----

func TestLoginSucceeds(t *testing.T) {
	u := testUser(t)
	u.FailedLoginAttempts = 3
	users, sessions := newFakeRepo(u), newFakeSessions()

	id, err := newAuth(t, users, sessions).Login(context.Background(), testEmail, testPassword, model.ClientMobile, "")
	if err != nil {
		t.Fatalf("ログインに失敗した: %v", err)
	}

	// DB にはセッション ID そのものではなく、ハッシュ値を保存する。
	s, ok := sessions.sessions[string(hashSessionID(id))]
	if !ok {
		t.Fatal("セッション ID のハッシュ値で保存されていない")
	}
	if s.UserID != u.ID || s.ClientType != model.ClientMobile || s.CSRFToken == "" {
		t.Errorf("保存したセッションが異なる: %+v", s)
	}
	if len(id) != 43 {
		t.Errorf("セッション ID は 32 バイトの乱数の base64url（43 文字）: %q", id)
	}
	if got := users.users[0].FailedLoginAttempts; got != 0 {
		t.Errorf("成功したら失敗の回数を 0 に戻す: %d", got)
	}
	if users.users[0].LastLoginAt == nil {
		t.Error("成功したら最終ログイン日時を記録する（ADR 0015）")
	}
}

// 失敗・ロック中・未登録では、最終ログイン日時を記録しない（ADR 0015）。
func TestLoginFailureDoesNotRecordLastLogin(t *testing.T) {
	locked := testUser(t)
	locked.ID, locked.Email = 2, "locked@example.com"
	locked.IsLocked, locked.FailedLoginAttempts = true, MaxLoginFailures
	users := newFakeRepo(testUser(t), locked)
	auth := newAuth(t, users, newFakeSessions())

	cases := []struct{ email, password string }{
		{testEmail, "wrong-password"},
		{"locked@example.com", testPassword},
		{"unknown@example.com", testPassword},
	}
	for _, c := range cases {
		if _, err := auth.Login(context.Background(), c.email, c.password, model.ClientWeb, ""); err == nil {
			t.Fatalf("%s: ログインに成功してしまった", c.email)
		}
	}
	for _, u := range users.users {
		if u.LastLoginAt != nil {
			t.Errorf("失敗では最終ログイン日時を記録しない: %+v", u)
		}
	}
}

func TestLoginNormalizesEmail(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	if _, err := newAuth(t, users, sessions).Login(context.Background(), "  Taro@Example.COM ", testPassword, model.ClientWeb, ""); err != nil {
		t.Fatalf("前後の空白と大文字を含むメールアドレスでログインできない: %v", err)
	}
}

func TestLoginRequiresEmailAndPassword(t *testing.T) {
	users := newFakeRepo(testUser(t))
	_, err := newAuth(t, users, newFakeSessions()).Login(context.Background(), " ", "", model.ClientWeb, "")

	issues := issuesOf(t, err)
	if !hasIssue(issues, "email", ReasonRequired) || !hasIssue(issues, "password", ReasonRequired) {
		t.Errorf("空のメールアドレスとパスワードの両方を返す: %+v", issues)
	}
	if users.users[0].FailedLoginAttempts != 0 {
		t.Error("空のときは失敗の回数を数えない")
	}
}

func TestLoginWrongPasswordCountsFailure(t *testing.T) {
	users := newFakeRepo(testUser(t))
	_, err := newAuth(t, users, newFakeSessions()).Login(context.Background(), testEmail, "wrong-password", model.ClientWeb, "")

	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("ErrInvalidCredentials ではない: %v", err)
	}
	if users.users[0].FailedLoginAttempts != 1 {
		t.Errorf("失敗の回数を 1 加算する: %d", users.users[0].FailedLoginAttempts)
	}
}

// 形式の検証はしない（ADR 0014）。登録時の規則に合わないパスワードも、照合して失敗になる。
func TestLoginDoesNotValidateFormat(t *testing.T) {
	users := newFakeRepo(testUser(t))
	_, err := newAuth(t, users, newFakeSessions()).Login(context.Background(), testEmail, "short", model.ClientWeb, "")

	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("形式の誤りも ErrInvalidCredentials になる: %v", err)
	}
	if users.users[0].FailedLoginAttempts != 1 {
		t.Error("登録済みのメールアドレスでの失敗として数える")
	}
}

func TestLoginUnknownOrDeletedEmail(t *testing.T) {
	deleted := testUser(t)
	deleted.ID, deleted.Email = 2, "deleted@example.com"
	now := fixedTime()
	deleted.DeletedAt = &now
	users := newFakeRepo(testUser(t), deleted)
	auth := newAuth(t, users, newFakeSessions())

	for _, email := range []string{"unknown@example.com", "deleted@example.com"} {
		_, err := auth.Login(context.Background(), email, testPassword, model.ClientWeb, "")
		if !errors.Is(err, ErrInvalidCredentials) {
			t.Errorf("%s: 未登録・削除済みは ErrInvalidCredentials: %v", email, err)
		}
	}
	for _, u := range users.users {
		if u.FailedLoginAttempts != 0 {
			t.Errorf("未登録・削除済みでは誰の回数も数えない: %+v", u)
		}
	}
}

func TestLoginLocksOnFifthFailure(t *testing.T) {
	u := testUser(t)
	u.FailedLoginAttempts = MaxLoginFailures - 1
	users := newFakeRepo(u)

	_, err := newAuth(t, users, newFakeSessions()).Login(context.Background(), testEmail, "wrong-password", model.ClientWeb, "")
	if !errors.Is(err, ErrAccountLocked) {
		t.Fatalf("5 回目の失敗は ErrAccountLocked: %v", err)
	}
	if !users.users[0].IsLocked || users.users[0].LockedAt == nil {
		t.Errorf("ロックされていない: %+v", users.users[0])
	}
}

func TestLoginWhileLockedDoesNotCheckPassword(t *testing.T) {
	u := testUser(t)
	u.IsLocked, u.FailedLoginAttempts = true, MaxLoginFailures
	users := newFakeRepo(u)
	auth := newAuth(t, users, newFakeSessions())

	for _, pw := range []string{testPassword, "wrong-password"} {
		_, err := auth.Login(context.Background(), testEmail, pw, model.ClientWeb, "")
		if !errors.Is(err, ErrAccountLocked) {
			t.Errorf("ロック中は正しいパスワードでも ErrAccountLocked: %v", err)
		}
	}
	if users.users[0].FailedLoginAttempts != MaxLoginFailures {
		t.Errorf("ロック中は数えない: %d", users.users[0].FailedLoginAttempts)
	}
}

// bcrypt は先頭 72 バイトしか見ないため、何もしなければ後ろに文字を足しても通ってしまう。
func TestLoginRejectsPasswordLongerThan72Bytes(t *testing.T) {
	password := strings.Repeat("a", 72)
	u := testUser(t)
	u.PasswordHash = hashOf(t, password)
	users := newFakeRepo(u)
	auth := newAuth(t, users, newFakeSessions())

	if _, err := auth.Login(context.Background(), testEmail, password+"x", model.ClientWeb, ""); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("72 バイトを超えるパスワードは一致しない扱い: %v", err)
	}
	if users.users[0].FailedLoginAttempts != 1 {
		t.Error("失敗として数える")
	}
	if _, err := auth.Login(context.Background(), testEmail, password, model.ClientWeb, ""); err != nil {
		t.Fatalf("72 文字ちょうどのパスワードではログインできる: %v", err)
	}
}

func TestLoginDeletesOldSessionOnlyOnSuccess(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	oldID, err := auth.Login(context.Background(), testEmail, testPassword, model.ClientWeb, "")
	if err != nil {
		t.Fatal(err)
	}

	// 失敗したログインでは、古いセッションを削除しない。
	if _, err := auth.Login(context.Background(), testEmail, "wrong-password", model.ClientWeb, oldID); err == nil {
		t.Fatal("誤ったパスワードでログインできた")
	}
	if _, ok := sessions.sessions[string(hashSessionID(oldID))]; !ok {
		t.Error("失敗したログインで古いセッションが削除された")
	}

	newID, err := auth.Login(context.Background(), testEmail, testPassword, model.ClientWeb, oldID)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := sessions.sessions[string(hashSessionID(oldID))]; ok {
		t.Error("成功したログインで古いセッションが削除されていない")
	}
	if _, ok := sessions.sessions[string(hashSessionID(newID))]; !ok || newID == oldID {
		t.Error("新しいセッションが発行されていない")
	}
}

// ---- セッションの確認 ----

func TestAuthenticate(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	id, err := auth.Login(context.Background(), testEmail, testPassword, model.ClientWeb, "")
	if err != nil {
		t.Fatal(err)
	}

	if s, err := auth.Authenticate(context.Background(), id); err != nil || s.UserID != 1 {
		t.Errorf("ログイン状態にあるセッションを確認できない: %+v, %v", s, err)
	}
	for _, bad := range []string{"", "unknown-session-id"} {
		if _, err := auth.Authenticate(context.Background(), bad); !errors.Is(err, ErrUnauthenticated) {
			t.Errorf("%q: ErrUnauthenticated ではない: %v", bad, err)
		}
	}
}

// ---- 本人によるパスワード変更 ----

func TestChangePasswordSucceeds(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)
	users.users[0].FailedLoginAttempts = 2

	if err := auth.ChangePassword(context.Background(), sess, testPassword, "new-password456"); err != nil {
		t.Fatalf("変更に失敗した: %v", err)
	}
	if bcrypt.CompareHashAndPassword([]byte(users.users[0].PasswordHash), []byte("new-password456")) != nil {
		t.Error("新しいパスワードで保存されていない")
	}
	// 今のセッションだけを残して、ほかのセッションを削除させる。
	if string(users.lastKeepSessionHash) != string(sess.IDHash) {
		t.Error("今のセッションを残すよう指示していない")
	}
	if users.users[0].FailedLoginAttempts != 0 {
		t.Error("照合に成功したら失敗の回数を 0 に戻す")
	}
}

func TestChangePasswordRequiresCurrentPassword(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)

	err := auth.ChangePassword(context.Background(), sess, "", "new-password456")
	if !hasIssue(issuesOf(t, err), "current_password", ReasonRequired) {
		t.Errorf("current_password の必須エラーではない: %v", err)
	}
	if users.users[0].FailedLoginAttempts != 0 {
		t.Error("空のときは数えない")
	}
}

func TestChangePasswordWrongCurrentPassword(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)

	err := auth.ChangePassword(context.Background(), sess, "wrong-password", "new-password456")
	if !hasIssue(issuesOf(t, err), "current_password", ReasonIncorrect) {
		t.Errorf("current_password の不一致エラーではない: %v", err)
	}
	if users.users[0].FailedLoginAttempts != 1 {
		t.Error("ログインと同じ回数に数える")
	}
	if users.updatePasswordCalls != 0 {
		t.Error("パスワードを変更してはいけない")
	}
}

// 新しいパスワードの形式の検証と、現在のパスワードの照合は両方行い、まとめて返す。
func TestChangePasswordReportsBothErrors(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)

	issues := issuesOf(t, auth.ChangePassword(context.Background(), sess, "wrong-password", "short"))
	if !hasIssue(issues, "current_password", ReasonIncorrect) || !hasIssue(issues, "new_password", ReasonTooShort) {
		t.Errorf("両方の誤りを返す: %+v", issues)
	}
	if users.users[0].FailedLoginAttempts != 1 {
		t.Error("新しいパスワードの形式が誤っていても、現在のパスワードの誤りは数える")
	}
}

func TestChangePasswordInvalidNewPasswordResetsFailures(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)
	users.users[0].FailedLoginAttempts = 3

	issues := issuesOf(t, auth.ChangePassword(context.Background(), sess, testPassword, "short"))
	if len(issues) != 1 || !hasIssue(issues, "new_password", ReasonTooShort) {
		t.Errorf("new_password の誤りだけを返す: %+v", issues)
	}
	if users.users[0].FailedLoginAttempts != 0 {
		t.Error("現在のパスワードの照合に成功したら 0 に戻す")
	}
}

func TestChangePasswordLocksAndDeletesSessionOnFifthFailure(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)
	other := login(t, auth, sessions) // 別の端末のセッション
	users.users[0].FailedLoginAttempts = MaxLoginFailures - 1

	err := auth.ChangePassword(context.Background(), sess, "wrong-password", "new-password456")
	if !errors.Is(err, ErrAccountLocked) {
		t.Fatalf("5 回目は ErrAccountLocked: %v", err)
	}
	if !users.users[0].IsLocked {
		t.Error("ロックされていない")
	}
	if _, ok := sessions.sessions[string(sess.IDHash)]; ok {
		t.Error("失敗させたセッションを削除する（強制ログアウト）")
	}
	if _, ok := sessions.sessions[string(other.IDHash)]; !ok {
		t.Error("ほかの端末のセッションは削除しない")
	}
}

func TestChangePasswordWhileLocked(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)
	// ログインの失敗で、ログイン中にロックされた場合。
	users.users[0].IsLocked, users.users[0].FailedLoginAttempts = true, MaxLoginFailures

	if err := auth.ChangePassword(context.Background(), sess, testPassword, "new-password456"); !errors.Is(err, ErrAccountLocked) {
		t.Fatalf("ロック中は照合せずに ErrAccountLocked: %v", err)
	}
	if users.users[0].FailedLoginAttempts != MaxLoginFailures {
		t.Error("ロック中は数えない")
	}
	if _, ok := sessions.sessions[string(sess.IDHash)]; !ok {
		t.Error("ログインでのロックではセッションを削除しない")
	}
}

func TestChangePasswordRejectsSamePassword(t *testing.T) {
	users, sessions := newFakeRepo(testUser(t)), newFakeSessions()
	auth := newAuth(t, users, sessions)
	sess := login(t, auth, sessions)

	err := auth.ChangePassword(context.Background(), sess, testPassword, testPassword)
	if !hasIssue(issuesOf(t, err), "new_password", ReasonSameAsCurrent) {
		t.Errorf("同じパスワードのエラーではない: %v", err)
	}
	if users.updatePasswordCalls != 0 {
		t.Error("パスワードを変更してはいけない")
	}
}

func TestChangePasswordCurrentPasswordLongerThan72Bytes(t *testing.T) {
	password := strings.Repeat("a", 72)
	u := testUser(t)
	u.PasswordHash = hashOf(t, password)
	users, sessions := newFakeRepo(u), newFakeSessions()
	auth := newAuth(t, users, sessions)
	id, err := auth.Login(context.Background(), testEmail, password, model.ClientWeb, "")
	if err != nil {
		t.Fatal(err)
	}
	sess := sessions.sessions[string(hashSessionID(id))]

	err = auth.ChangePassword(context.Background(), sess, password+"x", "new-password456")
	if !hasIssue(issuesOf(t, err), "current_password", ReasonIncorrect) {
		t.Errorf("72 バイトを超える現在のパスワードは一致しない扱い: %v", err)
	}
}

// ---- CSRF トークン ----

func TestPreLoginCSRF(t *testing.T) {
	auth := newAuth(t, newFakeRepo(), newFakeSessions())
	token, cookie := auth.NewPreLoginCSRF()

	if !auth.VerifyPreLoginCSRF(cookie, token) {
		t.Fatal("発行したトークンが照合に通らない")
	}

	otherToken, otherCookie := auth.NewPreLoginCSRF()
	tampered := token + "." + strings.Split(otherCookie, ".")[1]
	cases := map[string][2]string{
		"ヘッダーのトークンが異なる":     {cookie, otherToken},
		"ヘッダーがない":           {cookie, ""},
		"Cookie がない":        {"", token},
		"署名が別のトークンのもの":      {tampered, token},
		"署名のない Cookie":      {token, token},
		"別の秘密鍵で署名した Cookie": {signPreLoginCSRF([]byte("other-key"), token), token},
	}
	for name, c := range cases {
		if auth.VerifyPreLoginCSRF(c[0], c[1]) {
			t.Errorf("%s: 照合に通ってしまう", name)
		}
	}
}

func TestSessionCSRF(t *testing.T) {
	auth := newAuth(t, newFakeRepo(), newFakeSessions())
	sess := model.Session{CSRFToken: "token-in-session"}

	if !auth.VerifySessionCSRF(sess, "token-in-session") {
		t.Error("一致するトークンが照合に通らない")
	}
	for _, header := range []string{"", "other-token"} {
		if auth.VerifySessionCSRF(sess, header) {
			t.Errorf("%q: 照合に通ってしまう", header)
		}
	}
}
