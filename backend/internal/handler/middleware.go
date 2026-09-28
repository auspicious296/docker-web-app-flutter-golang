package handler

import (
	"context"
	"net/http"

	"backend/internal/model"
)

// csrfHeaderName は、Web アプリが CSRF トークンを送るヘッダー（ADR 0012）。
const csrfHeaderName = "X-CSRF-Token"

// credentialSource は、セッション ID がどこから送られてきたかを表す。
type credentialSource int

const (
	fromNone   credentialSource = iota
	fromCookie                  // Web：__Host-session の Cookie
	fromHeader                  // モバイル：Authorization: Bearer
)

// sessionContextKey は、ミドルウェアが確認したセッションを context に入れる鍵。
type sessionContextKey struct{}

// authContext は、ログインが必要な API のハンドラへ渡す情報。
type authContext struct {
	session model.Session
	source  credentialSource
}

func authFrom(r *http.Request) authContext {
	a, _ := r.Context().Value(sessionContextKey{}).(authContext)
	return a
}

// ミドルウェアが拒否するときの返答（ADR 0014）。
func writeUnauthenticated(w http.ResponseWriter) {
	writeError(w, http.StatusUnauthorized, "unauthenticated",
		"ログイン状態ではありません。ログインしてください。", nil)
}

func writeOriginNotAllowed(w http.ResponseWriter) {
	writeError(w, http.StatusForbidden, "origin_not_allowed",
		"許可されていない送信元からのリクエストです。", nil)
}

func writeCSRFTokenInvalid(w http.ResponseWriter) {
	writeError(w, http.StatusForbidden, "csrf_token_invalid",
		"リクエストを検証できませんでした。画面を再読み込みしてください。", nil)
}

func writeAmbiguousSession(w http.ResponseWriter) {
	writeError(w, http.StatusBadRequest, "ambiguous_session",
		"セッション ID が Cookie とヘッダーの両方で送られています。", nil)
}

// sessionCredential は、リクエストからセッション ID を取り出す。
//
// Cookie とヘッダーの両方に付いていたら ok を false にする（呼び出し側が 400 を
// 返す）。どちらか一方に決めると、Cookie で本人を確認したのに CSRF トークンの判定が
// 飛ばされる経路が生まれうるためである（ADR 0012）。Authorization ヘッダーが
// Bearer の形でなければ、セッション ID を空で返す（ログイン状態にない扱い）。
func sessionCredential(r *http.Request) (id string, source credentialSource, ok bool) {
	cookie := cookieValue(r, sessionCookieName)
	header := r.Header.Get("Authorization")

	switch {
	case cookie != "" && header != "":
		return "", fromNone, false
	case cookie != "":
		return cookie, fromCookie, true
	case header != "":
		return bearerToken(r), fromHeader, true
	default:
		return "", fromNone, true
	}
}

// isSafeMethod は、データを変更しないメソッドかを返す。GET ではデータを変更しない
// 前提のため、CSRF トークンと Origin の判定の対象外とする（ADR 0012）。
func isSafeMethod(method string) bool {
	return method == http.MethodGet || method == http.MethodHead
}

// requireWebOrigin は、Web 用の API で、Origin が許可したオリジンでなければ
// （ヘッダーがない場合を含めて）403 を返す（ADR 0012）。
func (h *AuthHandler) requireWebOrigin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Origin") != h.allowedOrigin {
			writeOriginNotAllowed(w)
			return
		}
		next(w, r)
	}
}

// rejectOrigin は、モバイル用のログイン API で、Origin が付いていたら 403 を返す。
// ブラウザ（Web アプリ）が誤ってモバイル用のパスを呼んだ場合を弾く（ADR 0012）。
func (h *AuthHandler) rejectOrigin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if len(r.Header.Values("Origin")) > 0 {
			writeOriginNotAllowed(w)
			return
		}
		next(w, r)
	}
}

// requireLogin は、ログインが必要な API の入り口。
//
// 判定の順序は「Cookie とヘッダーの両方 → Origin → セッション → CSRF トークン」。
// Origin と CSRF トークンの判定は、Cookie で本人を確認する、データを変更する
// リクエストだけに行う（ADR 0012）。Origin を先に見るのは、罠サイトからの
// リクエストを、セッションの確認（最後の操作日時の更新）より前に弾くためである。
func (h *AuthHandler) requireLogin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, source, ok := sessionCredential(r)
		if !ok {
			writeAmbiguousSession(w)
			return
		}

		checkCSRF := source == fromCookie && !isSafeMethod(r.Method)
		if checkCSRF && r.Header.Get("Origin") != h.allowedOrigin {
			writeOriginNotAllowed(w)
			return
		}

		sess, err := h.svc.Authenticate(r.Context(), id)
		if err != nil {
			writeServiceError(w, err)
			return
		}

		if checkCSRF && !h.svc.VerifySessionCSRF(sess, r.Header.Get(csrfHeaderName)) {
			writeCSRFTokenInvalid(w)
			return
		}

		ctx := context.WithValue(r.Context(), sessionContextKey{}, authContext{session: sess, source: source})
		next(w, r.WithContext(ctx))
	}
}
