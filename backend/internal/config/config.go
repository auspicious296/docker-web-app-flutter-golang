// Package config は、API が起動時に必要とする環境変数を読み込む。
//
// どの値もコードに初期値を持たせない。1 つでも未設定・不正なら Load がエラーを
// 返し、API は起動時に中止する（ADR 0012・0013・0014）。
package config

import (
	"errors"
	"fmt"
	"os"
	"time"
)

// Config は環境変数から読み込んだ設定。
type Config struct {
	DatabaseURL string

	// CSRFSigningKey は、ログイン前の CSRF トークンの署名に使う秘密鍵（ADR 0012）。
	CSRFSigningKey []byte

	// AllowedOrigin は、Web 用の API で許可するオリジン（ADR 0014）。
	AllowedOrigin string

	// ログイン状態の保持期間（ADR 0013）。
	WebIdleTimeout        time.Duration
	WebAbsoluteTimeout    time.Duration
	MobileIdleTimeout     time.Duration
	MobileAbsoluteTimeout time.Duration
}

// Load は環境変数を読み込む。問題のあった変数をすべてまとめてエラーで返す。
func Load() (Config, error) {
	var errs []error

	str := func(name string) string {
		v := os.Getenv(name)
		if v == "" {
			errs = append(errs, fmt.Errorf("環境変数 %s が設定されていません", name))
		}
		return v
	}

	dur := func(name string) time.Duration {
		s := str(name)
		if s == "" {
			return 0
		}
		d, err := time.ParseDuration(s)
		if err != nil || d <= 0 {
			errs = append(errs, fmt.Errorf("環境変数 %s の値 %q は正の時間として解釈できません（例：30m、8h、720h）", name, s))
		}
		return d
	}

	cfg := Config{
		DatabaseURL:           str("DATABASE_URL"),
		CSRFSigningKey:        []byte(str("CSRF_SIGNING_KEY")),
		AllowedOrigin:         str("ALLOWED_ORIGIN"),
		WebIdleTimeout:        dur("SESSION_WEB_IDLE_TIMEOUT"),
		WebAbsoluteTimeout:    dur("SESSION_WEB_ABSOLUTE_TIMEOUT"),
		MobileIdleTimeout:     dur("SESSION_MOBILE_IDLE_TIMEOUT"),
		MobileAbsoluteTimeout: dur("SESSION_MOBILE_ABSOLUTE_TIMEOUT"),
	}

	if len(errs) > 0 {
		return Config{}, errors.Join(errs...)
	}
	return cfg, nil
}
