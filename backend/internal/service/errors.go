package service

import (
	"errors"
	"fmt"
	"strings"
)

// この層が返すエラー。
//
// service は「何が起きたか」だけを返し、HTTP のステータスコード・API の
// エラーコード・利用者に見せる日本語の文言は handler が持つ（ADR 0004）。
var (
	// ErrUserNotFound は、対象のユーザーが存在しないか、削除済みであることを表す。
	ErrUserNotFound = errors.New("service: user not found")
	// ErrEmailAlreadyExists は、生存しているユーザーとメールアドレスが重複したことを表す。
	ErrEmailAlreadyExists = errors.New("service: email already exists")
	// ErrEmailBelongsToDeletedUser は、削除済みのユーザーとメールアドレスが重複したことを表す。
	ErrEmailBelongsToDeletedUser = errors.New("service: email belongs to deleted user")

	// ErrInvalidCredentials は、ログインでメールアドレスが未登録（削除済みを含む）か、
	// パスワードが誤っていたことを表す。どちらなのかは区別しない（ADR 0014）。
	ErrInvalidCredentials = errors.New("service: invalid credentials")
	// ErrAccountLocked は、アカウントがロックされている（今回の失敗でロックされた
	// 場合を含む）ことを表す。
	ErrAccountLocked = errors.New("service: account locked")
	// ErrUnauthenticated は、セッションがない、またはログイン状態にないことを表す。
	ErrUnauthenticated = errors.New("service: unauthenticated")
)

// Reason は、入力値がなぜ不正なのかを表す。対応する日本語の文言は handler が持つ。
type Reason int

const (
	ReasonRequired      Reason = iota // 必須の項目が空
	ReasonTooLong                     // 文字数が上限を超えている
	ReasonTooShort                    // 文字数が下限に満たない
	ReasonInvalidFormat               // 形式が不正
	ReasonOutOfRange                  // 値が許容範囲の外
	ReasonIncorrect                   // 現在のパスワードが一致しない
	ReasonSameAsCurrent               // 新しいパスワードが現在のパスワードと同じ
)

func (r Reason) String() string {
	switch r {
	case ReasonRequired:
		return "required"
	case ReasonTooLong:
		return "too_long"
	case ReasonTooShort:
		return "too_short"
	case ReasonInvalidFormat:
		return "invalid_format"
	case ReasonOutOfRange:
		return "out_of_range"
	case ReasonIncorrect:
		return "incorrect"
	case ReasonSameAsCurrent:
		return "same_as_current"
	default:
		return fmt.Sprintf("unknown(%d)", int(r))
	}
}

// Issue は、どの項目がどういう理由で不正かを表す。
type Issue struct {
	Field  string
	Reason Reason
}

// ValidationError は入力値の検証に失敗したことを表す。
//
// 1 つ目の不正で打ち切らず、不正だった項目をすべて Issues に入れて返す。
type ValidationError struct {
	Issues []Issue
}

func (e *ValidationError) Error() string {
	parts := make([]string, 0, len(e.Issues))
	for _, i := range e.Issues {
		parts = append(parts, i.Field+": "+i.Reason.String())
	}
	return "service: validation failed (" + strings.Join(parts, ", ") + ")"
}

// validator は検証中の Issue を溜める。
type validator struct {
	issues []Issue
}

func (v *validator) add(field string, reason Reason) {
	v.issues = append(v.issues, Issue{Field: field, Reason: reason})
}

// has は、その項目に不正が 1 件でもあるかを返す。
func (v *validator) has(field string) bool {
	for _, i := range v.issues {
		if i.Field == field {
			return true
		}
	}
	return false
}

// err は、1 件でも不正があれば *ValidationError を、なければ nil を返す。
func (v *validator) err() error {
	if len(v.issues) == 0 {
		return nil
	}
	return &ValidationError{Issues: v.issues}
}

// NewValidationError は、handler がクエリパラメータの不正を同じ形で返すために使う。
func NewValidationError(issues ...Issue) *ValidationError {
	return &ValidationError{Issues: issues}
}
