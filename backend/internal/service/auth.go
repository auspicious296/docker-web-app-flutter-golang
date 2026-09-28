package service

import (
	"context"
	"errors"
	"strings"

	"golang.org/x/crypto/bcrypt"

	"backend/internal/model"
	"backend/internal/repository"
)

// MaxLoginFailures は、ロックするまでに許す、パスワードの照合の連続した失敗の回数。
// ログインと、本人によるパスワード変更での現在のパスワードの照合で共通に数える
// （ADR 0014）。
const MaxLoginFailures = 5

// bcryptMaxBytes は、bcrypt がパスワードとして使う先頭のバイト数の上限。
// bcrypt.CompareHashAndPassword はこれを超える入力を拒否せず、先頭だけで照合する。
const bcryptMaxBytes = 72

// AuthUserRepository は、AuthService が users テーブルに対して必要とする操作。
type AuthUserRepository interface {
	FindByID(ctx context.Context, id int64, includeDeleted bool) (model.User, error)
	FindActiveByEmail(ctx context.Context, email string) (model.User, error)
	RecordLoginFailure(ctx context.Context, id int64, maxAttempts int) (bool, error)
	ResetLoginFailures(ctx context.Context, id int64) error
	RecordLoginSuccess(ctx context.Context, id int64) error
	UpdatePassword(ctx context.Context, id int64, passwordHash string, keepSessionHash []byte) (model.User, error)
}

// SessionRepository は、AuthService が sessions テーブルに対して必要とする操作。
type SessionRepository interface {
	Create(ctx context.Context, idHash []byte, userID int64, clientType, csrfToken string) error
	Touch(ctx context.Context, idHash []byte, timeouts model.SessionTimeouts) (model.Session, error)
	Delete(ctx context.Context, idHash []byte) error
	DeleteExpired(ctx context.Context, timeouts model.SessionTimeouts) (int64, error)
}

// AuthConfig は AuthService の設定値。
type AuthConfig struct {
	// BcryptCost は、UserService がパスワードのハッシュ化に使う値と同じにする。
	// ダミーのハッシュ値の照合にかかる時間を、本物の照合と揃えるためである。
	BcryptCost int
	Timeouts   model.SessionTimeouts
	// CSRFSigningKey は、ログイン前の CSRF トークンの署名に使う秘密鍵（ADR 0012）。
	CSRFSigningKey []byte
}

// AuthService は、ログイン・ログアウト・セッション・本人によるパスワード変更の
// 業務ロジックを提供する（ADR 0012・0013・0014）。
type AuthService struct {
	users    AuthUserRepository
	sessions SessionRepository
	cfg      AuthConfig

	// dummyHash は、照合する相手がいないとき（未登録のメールアドレスなど）にも
	// bcrypt の照合を行い、応答時間を揃えるためのハッシュ値（ADR 0014）。
	dummyHash []byte
}

func NewAuthService(users AuthUserRepository, sessions SessionRepository, cfg AuthConfig) (*AuthService, error) {
	dummy, err := bcrypt.GenerateFromPassword([]byte(newToken()), cfg.BcryptCost)
	if err != nil {
		return nil, err
	}
	return &AuthService{users: users, sessions: sessions, cfg: cfg, dummyHash: dummy}, nil
}

// Login はメールアドレスとパスワードを照合し、新しいセッションを発行して
// セッション ID を返す（ADR 0014）。
//
// clientType は、どちらのログイン API を通ったか（model.ClientWeb / ClientMobile）。
// oldSessionID には、リクエストに付いていた古いセッション ID を渡す（なければ空）。
// ログインに成功したら、古いセッションは削除する。
func (s *AuthService) Login(ctx context.Context, email, password, clientType, oldSessionID string) (string, error) {
	// 登録時と同じく、前後の空白を除いて小文字にしてから照合する（ADR 0002）。
	email = strings.ToLower(strings.TrimSpace(email))

	// 入力の検証は「空かどうか」だけ。登録時の形式の規則は使わない（ADR 0014）。
	v := &validator{}
	if email == "" {
		v.add("email", ReasonRequired)
	}
	if password == "" {
		v.add("password", ReasonRequired)
	}
	if err := v.err(); err != nil {
		return "", err
	}

	u, err := s.users.FindActiveByEmail(ctx, email)
	if errors.Is(err, repository.ErrNotFound) {
		// 未登録でも照合と同じだけ時間をかけ、応答時間から登録の有無を
		// 知られないようにする。失敗の回数は数えない（対象のユーザーがいない）。
		s.burnPasswordCheck(password)
		return "", ErrInvalidCredentials
	}
	if err != nil {
		return "", err
	}

	// ロック中はパスワードを照合せず、失敗の回数も数えない（ADR 0014）。
	if u.IsLocked {
		return "", ErrAccountLocked
	}

	if !s.passwordMatches(u.PasswordHash, password) {
		locked, err := s.countFailure(ctx, u.ID)
		if err != nil {
			return "", err
		}
		if locked {
			return "", ErrAccountLocked
		}
		return "", ErrInvalidCredentials
	}

	if oldSessionID != "" {
		if err := s.sessions.Delete(ctx, hashSessionID(oldSessionID)); err != nil {
			return "", err
		}
	}

	sessionID := newToken()
	if err := s.sessions.Create(ctx, hashSessionID(sessionID), u.ID, clientType, newToken()); err != nil {
		return "", err
	}

	// 失敗の回数を 0 に戻し、最終ログイン日時を入れる（ADR 0015）。セッションを
	// 作成できた後に行い、ログインが成立したときだけ記録する。
	if err := s.users.RecordLoginSuccess(ctx, u.ID); err != nil {
		return "", err
	}
	return sessionID, nil
}

// Authenticate は、セッション ID がログイン状態にあるセッションのものかを確かめ、
// 最後の操作日時を更新してセッションを返す。ログイン状態になければ
// ErrUnauthenticated を返す。
func (s *AuthService) Authenticate(ctx context.Context, sessionID string) (model.Session, error) {
	if sessionID == "" {
		return model.Session{}, ErrUnauthenticated
	}
	sess, err := s.sessions.Touch(ctx, hashSessionID(sessionID), s.cfg.Timeouts)
	if errors.Is(err, repository.ErrNotFound) {
		return model.Session{}, ErrUnauthenticated
	}
	return sess, err
}

// Logout はセッションを削除する。
func (s *AuthService) Logout(ctx context.Context, sess model.Session) error {
	return s.sessions.Delete(ctx, sess.IDHash)
}

// Me は、セッションの持ち主のユーザーを返す。
func (s *AuthService) Me(ctx context.Context, sess model.Session) (model.User, error) {
	u, err := s.users.FindByID(ctx, sess.UserID, false)
	if errors.Is(err, repository.ErrNotFound) {
		// ユーザーを削除するとセッションも削除するため、通常は起こらない。
		return model.User{}, ErrUnauthenticated
	}
	return u, err
}

// ChangePassword は、本人によるパスワード変更を行う（ADR 0014）。
//
// 新しいパスワードの形式の検証と、現在のパスワードの照合は両方行い、不正を
// まとめて *ValidationError で返す。現在のパスワードの誤りはログインと同じ回数に
// 数え、5 回連続で誤ったらロックし、そのセッションを削除して ErrAccountLocked を
// 返す。成功したら、今のセッション以外のセッションを削除する（ADR 0012）。
func (s *AuthService) ChangePassword(ctx context.Context, sess model.Session, currentPassword, newPassword string) error {
	u, err := s.users.FindByID(ctx, sess.UserID, false)
	if errors.Is(err, repository.ErrNotFound) {
		return ErrUnauthenticated
	}
	if err != nil {
		return err
	}

	// ロック中は照合せず、失敗の回数も数えない（ログインと同じ扱い）。
	if u.IsLocked {
		return ErrAccountLocked
	}

	v := &validator{}
	validatePassword(v, "new_password", newPassword)

	if currentPassword == "" {
		v.add("current_password", ReasonRequired)
	} else if !s.passwordMatches(u.PasswordHash, currentPassword) {
		locked, err := s.countFailure(ctx, u.ID)
		if err != nil {
			return err
		}
		if locked {
			// 本人確認に続けて失敗したセッションは乗っ取りを疑うべきため、
			// 失敗させたそのセッションを削除する（強制ログアウト）。
			if err := s.sessions.Delete(ctx, sess.IDHash); err != nil {
				return err
			}
			return ErrAccountLocked
		}
		v.add("current_password", ReasonIncorrect)
	} else {
		if u.FailedLoginAttempts > 0 {
			if err := s.users.ResetLoginFailures(ctx, u.ID); err != nil {
				return err
			}
		}
		if !v.has("new_password") && newPassword == currentPassword {
			v.add("new_password", ReasonSameAsCurrent)
		}
	}

	if err := v.err(); err != nil {
		return err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), s.cfg.BcryptCost)
	if err != nil {
		return err
	}
	if _, err := s.users.UpdatePassword(ctx, u.ID, string(hash), sess.IDHash); err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			return ErrUnauthenticated
		}
		return err
	}
	return nil
}

// NewPreLoginCSRF は、ログイン前の CSRF トークンと、それを署名した Cookie の値を返す。
func (s *AuthService) NewPreLoginCSRF() (token, cookieValue string) {
	token = newToken()
	return token, signPreLoginCSRF(s.cfg.CSRFSigningKey, token)
}

// VerifyPreLoginCSRF は、ログイン前の CSRF トークンを照合する。
func (s *AuthService) VerifyPreLoginCSRF(cookieValue, headerToken string) bool {
	return verifyPreLoginCSRF(s.cfg.CSRFSigningKey, cookieValue, headerToken)
}

// VerifySessionCSRF は、ログイン後の CSRF トークンを、セッションの行に保存した
// トークンと照合する。
func (s *AuthService) VerifySessionCSRF(sess model.Session, headerToken string) bool {
	return tokensEqual(sess.CSRFToken, headerToken)
}

// DeleteExpiredSessions は、ログイン状態にない（タイムアウトした）セッションを削除し、
// 削除した件数を返す。
func (s *AuthService) DeleteExpiredSessions(ctx context.Context) (int64, error) {
	return s.sessions.DeleteExpired(ctx, s.cfg.Timeouts)
}

// passwordMatches は、入力されたパスワードが保存済みのハッシュ値と完全に一致するかを返す。
//
// 72 バイトを超えるパスワードは、bcrypt が先頭 72 バイトしか見ないため、そのまま
// 照合すると後ろに余計な文字を付けても一致してしまう。照合に使わず「一致しない」と
// 扱う。ただし応答時間を揃えるため、ダミーのハッシュ値で照合は行う（ADR 0014）。
func (s *AuthService) passwordMatches(hash, password string) bool {
	if len(password) > bcryptMaxBytes {
		s.burnPasswordCheck(password)
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// burnPasswordCheck は、結果を使わない照合で、本物の照合と同じだけ時間をかける。
func (s *AuthService) burnPasswordCheck(password string) {
	_ = bcrypt.CompareHashAndPassword(s.dummyHash, []byte(password))
}

// countFailure は照合の失敗を 1 回数え、ロックしたかを返す。
//
// 加算の直前に別のリクエストがロックした（または削除した）場合、repository は
// ErrNotFound を返す。その場合は現在の状態を読み直し、ロックされていれば
// ロックとして扱う。
func (s *AuthService) countFailure(ctx context.Context, userID int64) (bool, error) {
	locked, err := s.users.RecordLoginFailure(ctx, userID, MaxLoginFailures)
	if !errors.Is(err, repository.ErrNotFound) {
		return locked, err
	}

	u, err := s.users.FindByID(ctx, userID, false)
	if errors.Is(err, repository.ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return u.IsLocked, nil
}
