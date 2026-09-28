package handler

import "net/http"

// Cookie の名前。__Host- で始めると、ブラウザが Secure・Path=/・Domain 指定なしを
// 強制する（ADR 0012）。
const (
	// sessionCookieName は、Web のセッション ID を入れる Cookie。
	sessionCookieName = "__Host-session"
	// preLoginCSRFCookieName は、ログイン前の CSRF トークンを署名して入れる Cookie。
	preLoginCSRFCookieName = "__Host-csrf"
)

// setCookie は、ADR 0012 の属性（HttpOnly・Secure・SameSite=Strict）で Cookie を発行する。
//
// 有効期限は付けない。ブラウザを閉じると消える（ADR 0013）。
func setCookie(w http.ResponseWriter, name, value string) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/",
		Secure:   true,
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
	})
}

// clearCookie は、有効期限切れの Cookie を送って、ブラウザに Cookie を消させる。
func clearCookie(w http.ResponseWriter, name string) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		Secure:   true,
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
	})
}

// cookieValue は Cookie の値を返す。付いていなければ空文字を返す。
func cookieValue(r *http.Request, name string) string {
	c, err := r.Cookie(name)
	if err != nil {
		return ""
	}
	return c.Value
}
