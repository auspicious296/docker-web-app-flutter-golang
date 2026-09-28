package handler

import (
	"errors"
	"net/http"
	"strings"

	"backend/internal/model"
	"backend/internal/service"
)

// AuthHandler は、ログイン・ログアウト・本人の情報・本人によるパスワード変更の
// API のハンドラ（ADR 0012・0014）。
type AuthHandler struct {
	svc *service.AuthService
	// allowedOrigin は、Web 用の API で許可するオリジン（環境変数 ALLOWED_ORIGIN）。
	allowedOrigin string
}

func NewAuthHandler(svc *service.AuthService, allowedOrigin string) *AuthHandler {
	return &AuthHandler{svc: svc, allowedOrigin: allowedOrigin}
}

// Register はルートを登録する。
//
// ログイン前に呼べるのは、CSRF トークンの発行と 2 つのログイン API だけ。
// それ以外はログインが必要な API として requireLogin を通す。
func (h *AuthHandler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/csrf-token", h.csrfToken)
	mux.HandleFunc("POST /api/login", h.requireWebOrigin(h.webLogin))
	mux.HandleFunc("POST /api/mobile/login", h.rejectOrigin(h.mobileLogin))
	mux.HandleFunc("POST /api/logout", h.requireLogin(h.logout))
	mux.HandleFunc("GET /api/me", h.requireLogin(h.me))
	mux.HandleFunc("PUT /api/me/password", h.requireLogin(h.changePassword))
}

// csrfToken は CSRF トークンを返す（ADR 0012）。
//
// ログイン状態にあるセッションが付いていれば、そのセッションのトークンを返す。
// なければ、署名付きの Cookie を発行してログイン前のトークンを返す。
func (h *AuthHandler) csrfToken(w http.ResponseWriter, r *http.Request) {
	id, _, ok := sessionCredential(r)
	if !ok {
		writeAmbiguousSession(w)
		return
	}

	var token string
	sess, err := h.svc.Authenticate(r.Context(), id)
	switch {
	case err == nil:
		token = sess.CSRFToken
	case errors.Is(err, service.ErrUnauthenticated):
		var signed string
		token, signed = h.svc.NewPreLoginCSRF()
		setCookie(w, preLoginCSRFCookieName, signed)
	default:
		writeServiceError(w, err)
		return
	}

	// トークンをキャッシュに残させない。圧縮もしない（BREACH 攻撃の対策。ADR 0012）。
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, csrfTokenResponse{CSRFToken: token})
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// webLogin は Web 用のログイン（POST /api/login）。
//
// ログイン前の CSRF トークンを照合してからログインする。成功したら、セッション ID を
// Cookie だけで渡し、本文には決して含めない（ADR 0012）。
func (h *AuthHandler) webLogin(w http.ResponseWriter, r *http.Request) {
	if !h.svc.VerifyPreLoginCSRF(cookieValue(r, preLoginCSRFCookieName), r.Header.Get(csrfHeaderName)) {
		writeCSRFTokenInvalid(w)
		return
	}

	var req loginRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	sessionID, err := h.svc.Login(r.Context(), req.Email, req.Password, model.ClientWeb,
		cookieValue(r, sessionCookieName))
	if err != nil {
		writeServiceError(w, err)
		return
	}

	setCookie(w, sessionCookieName, sessionID)
	// ログイン前のトークンは引き継がない（ADR 0012）。
	clearCookie(w, preLoginCSRFCookieName)
	w.WriteHeader(http.StatusNoContent)
}

// mobileLogin はモバイル用のログイン（POST /api/mobile/login）。セッション ID を本文で返す。
func (h *AuthHandler) mobileLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	sessionID, err := h.svc.Login(r.Context(), req.Email, req.Password, model.ClientMobile,
		bearerToken(r))
	if err != nil {
		writeServiceError(w, err)
		return
	}

	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, mobileLoginResponse{SessionID: sessionID})
}

// logout はセッションを削除する。Web では Cookie も消させる。
func (h *AuthHandler) logout(w http.ResponseWriter, r *http.Request) {
	a := authFrom(r)
	if err := h.svc.Logout(r.Context(), a.session); err != nil {
		writeServiceError(w, err)
		return
	}

	if a.source == fromCookie {
		clearCookie(w, sessionCookieName)
	}
	w.WriteHeader(http.StatusNoContent)
}

// me はログイン中のユーザーの情報を返す。
func (h *AuthHandler) me(w http.ResponseWriter, r *http.Request) {
	u, err := h.svc.Me(r.Context(), authFrom(r).session)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, meResponse{ID: u.ID, Name: u.Name, Email: u.Email})
}

// changePassword は本人によるパスワード変更（PUT /api/me/password）。
//
// 5 回連続で現在のパスワードを誤ると、service がそのセッションを削除して
// ErrAccountLocked を返す。Web の Cookie は消させない。削除済みのセッションの
// Cookie は、次のリクエストで 401 になるだけで害がないためである。
func (h *AuthHandler) changePassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}

	if err := h.svc.ChangePassword(r.Context(), authFrom(r).session, req.CurrentPassword, req.NewPassword); err != nil {
		writeServiceError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// bearerToken は、Authorization: Bearer で送られたセッション ID を返す。なければ空文字。
func bearerToken(r *http.Request) string {
	scheme, token, found := strings.Cut(r.Header.Get("Authorization"), " ")
	if !found || !strings.EqualFold(scheme, "Bearer") {
		return ""
	}
	return strings.TrimSpace(token)
}

type csrfTokenResponse struct {
	CSRFToken string `json:"csrf_token"`
}

type mobileLoginResponse struct {
	SessionID string `json:"session_id"`
}

// meResponse は GET /api/me のレスポンス。本人に必要な 3 項目だけを返す（ADR 0014）。
type meResponse struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
}
