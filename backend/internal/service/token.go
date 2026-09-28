package service

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"strings"
)

// tokenBytes は、セッション ID と CSRF トークンの乱数のバイト数（ADR 0012）。
const tokenBytes = 32

// newToken は、推測できない乱数から作ったトークンを返す。
//
// 32 バイトの乱数を、URL・Cookie・ヘッダーにそのまま載せられる base64url
// （パディングなし、43 文字）にする。crypto/rand.Read はエラーを返さない。
func newToken() string {
	b := make([]byte, tokenBytes)
	rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// hashSessionID は、DB に保存するセッション ID のハッシュ値を返す。
//
// セッション ID は推測できない乱数のため、わざと遅い bcrypt ではなく SHA-256 で
// 十分である（ADR 0012）。
func hashSessionID(sessionID string) []byte {
	sum := sha256.Sum256([]byte(sessionID))
	return sum[:]
}

// tokensEqual は 2 つのトークンを、比較にかかる時間から値を推測されないように
// 比べる（ADR 0012）。空のトークンは一致とみなさない。
func tokensEqual(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

// preLoginCSRFLabel は、ログイン前の CSRF トークンの署名に混ぜる用途の名前。
// 同じ秘密鍵で別の用途の署名を作った場合に、取り違えて通らないようにする。
const preLoginCSRFLabel = "pre-login-csrf:"

// signPreLoginCSRF は、ログイン前の CSRF トークンの Cookie に入れる値
// 「トークン.署名」を返す（署名付きダブルサブミット Cookie。ADR 0012）。
func signPreLoginCSRF(key []byte, token string) string {
	return token + "." + preLoginCSRFSignature(key, token)
}

// verifyPreLoginCSRF は、Cookie の値の署名が正しく、かつヘッダーで送られた
// トークンが Cookie の中のトークンと一致するかを返す。
func verifyPreLoginCSRF(key []byte, cookieValue, headerToken string) bool {
	token, sig, ok := strings.Cut(cookieValue, ".")
	if !ok {
		return false
	}
	if !tokensEqual(sig, preLoginCSRFSignature(key, token)) {
		return false
	}
	return tokensEqual(token, headerToken)
}

func preLoginCSRFSignature(key []byte, token string) string {
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(preLoginCSRFLabel + token))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
