// Package service は、入力値の整形・検証、パスワードのハッシュ化、業務上の
// ルール（メールアドレスの重複の扱いなど）を担う。
//
// HTTP も SQL も知らない。DB 固有のエラーは repository がこの層の外で翻訳し、
// HTTP への変換は handler が行う。
package service

import (
	"context"
	"errors"
	"net/mail"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"

	"backend/internal/model"
	"backend/internal/repository"
)

// 入力値の制限とページングの既定値。
const (
	MaxNameLength     = 255
	MaxEmailLength    = 255
	MinPasswordLength = 8
	// MaxPasswordLength は bcrypt が 73 バイト目以降を無視することに由来する上限。
	// 使える文字を ASCII の印字可能文字に限ったため、バイト数と文字数が一致する
	// （ADR 0008）。
	MaxPasswordLength = 72

	DefaultPage    = 1
	DefaultPerPage = 20
	MaxPerPage     = 100
)

// UserRepository は service が必要とする DB 操作。
//
// テストでは手書きのフェイクに差し替えるため、実装側ではなくこの層で定義する。
type UserRepository interface {
	List(ctx context.Context, includeDeleted bool, limit, offset int) ([]model.User, error)
	Count(ctx context.Context, includeDeleted bool) (int, error)
	FindByID(ctx context.Context, id int64, includeDeleted bool) (model.User, error)
	FindByEmail(ctx context.Context, email string) (model.User, error)
	Create(ctx context.Context, name, email, passwordHash string) (model.User, error)
	Update(ctx context.Context, id int64, name, email string) (model.User, error)
	UpdatePassword(ctx context.Context, id int64, passwordHash string, keepSessionHash []byte) (model.User, error)
	Unlock(ctx context.Context, id int64) (model.User, error)
	SoftDelete(ctx context.Context, id int64) (model.User, error)
}

// UserService はユーザー管理の業務ロジックを提供する。
type UserService struct {
	repo UserRepository
	// bcryptCost はハッシュ化の繰り返し回数（2 の bcryptCost 乗）。本番では
	// bcrypt.DefaultCost、テストでは bcrypt.MinCost を渡す（ADR 0003）。
	bcryptCost int
}

func NewUserService(repo UserRepository, bcryptCost int) *UserService {
	return &UserService{repo: repo, bcryptCost: bcryptCost}
}

// List はユーザーの一覧と、同じ条件での総件数を返す。
func (s *UserService) List(ctx context.Context, page, perPage int, includeDeleted bool) ([]model.User, int, error) {
	total, err := s.repo.Count(ctx, includeDeleted)
	if err != nil {
		return nil, 0, err
	}

	users, err := s.repo.List(ctx, includeDeleted, perPage, (page-1)*perPage)
	if err != nil {
		return nil, 0, err
	}
	return users, total, nil
}

// Get はユーザーを 1 件返す。
func (s *UserService) Get(ctx context.Context, id int64, includeDeleted bool) (model.User, error) {
	u, err := s.repo.FindByID(ctx, id, includeDeleted)
	return u, toNotFound(err)
}

// Create はユーザーを登録する。
//
// メールアドレスが既存の行と衝突した場合、相手が生存しているか削除済みかで
// 異なるエラーを返す（ADR 0004）。削除済みの行を復帰させることはしない。
func (s *UserService) Create(ctx context.Context, name, email, password string) (model.User, error) {
	name = normalizeName(name)
	email = strings.TrimSpace(email)

	v := &validator{}
	validateName(v, name)
	validateEmail(v, email)
	validatePassword(v, "password", password)
	if err := v.err(); err != nil {
		return model.User{}, err
	}
	email = strings.ToLower(email)

	if err := s.checkEmailConflict(ctx, email, 0); err != nil {
		return model.User{}, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), s.bcryptCost)
	if err != nil {
		return model.User{}, err
	}

	created, err := s.repo.Create(ctx, name, email, string(hash))
	if errors.Is(err, repository.ErrDuplicateEmail) {
		// 事前の検索と INSERT の間に、別のリクエストが同じアドレスを登録した場合。
		return model.User{}, ErrEmailAlreadyExists
	}
	if err != nil {
		return model.User{}, err
	}
	return created, nil
}

// Update は名前とメールアドレスを更新する（全項目の置き換え）。
func (s *UserService) Update(ctx context.Context, id int64, name, email string) (model.User, error) {
	name = normalizeName(name)
	email = strings.TrimSpace(email)

	v := &validator{}
	validateName(v, name)
	validateEmail(v, email)
	if err := v.err(); err != nil {
		return model.User{}, err
	}
	email = strings.ToLower(email)

	// 削除済みのユーザーは更新の対象にしない。
	if _, err := s.repo.FindByID(ctx, id, false); err != nil {
		return model.User{}, toNotFound(err)
	}

	if err := s.checkEmailConflict(ctx, email, id); err != nil {
		return model.User{}, err
	}

	updated, err := s.repo.Update(ctx, id, name, email)
	if errors.Is(err, repository.ErrDuplicateEmail) {
		return model.User{}, ErrEmailAlreadyExists
	}
	if err != nil {
		return model.User{}, toNotFound(err)
	}
	return updated, nil
}

// ResetPassword は管理者によるパスワードの上書き。現在のパスワードとの照合は行わない。
//
// そのユーザーの全セッションを削除する（ADR 0012）。
func (s *UserService) ResetPassword(ctx context.Context, id int64, password string) (model.User, error) {
	v := &validator{}
	validatePassword(v, "password", password)
	if err := v.err(); err != nil {
		return model.User{}, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), s.bcryptCost)
	if err != nil {
		return model.User{}, err
	}

	updated, err := s.repo.UpdatePassword(ctx, id, string(hash), nil)
	return updated, toNotFound(err)
}

// Unlock はアカウントロックを解除する。
//
// ロックされていないユーザーに対して実行してもエラーにしない。結果として
// 望む状態（ロックされていない）になっているため（ADR 0004）。
func (s *UserService) Unlock(ctx context.Context, id int64) (model.User, error) {
	u, err := s.repo.Unlock(ctx, id)
	return u, toNotFound(err)
}

// Delete は論理削除する。そのユーザーの全セッションも削除する（ADR 0012）。
func (s *UserService) Delete(ctx context.Context, id int64) (model.User, error) {
	u, err := s.repo.SoftDelete(ctx, id)
	return u, toNotFound(err)
}

// checkEmailConflict は、そのメールアドレスが他の行で使われていないかを調べる。
//
// selfID に 0 以外を渡すと、その id の行は「自分自身」とみなして重複扱いしない
// （名前だけを変更したいときに 409 にならないようにするため）。
func (s *UserService) checkEmailConflict(ctx context.Context, email string, selfID int64) error {
	existing, err := s.repo.FindByEmail(ctx, email)
	switch {
	case errors.Is(err, repository.ErrNotFound):
		return nil
	case err != nil:
		return err
	case existing.ID == selfID:
		return nil
	case existing.DeletedAt == nil:
		return ErrEmailAlreadyExists
	default:
		return ErrEmailBelongsToDeletedUser
	}
}

// toNotFound は repository の「該当なし」をこの層のエラーへ変換する。
func toNotFound(err error) error {
	if errors.Is(err, repository.ErrNotFound) {
		return ErrUserNotFound
	}
	return err
}

// normalizeName は表示名を整形する。
//
// 姓名の間の全角空白は半角に変換し、前後の空白（半角・全角とも
// strings.TrimSpace の対象）を削除する。
func normalizeName(name string) string {
	return strings.TrimSpace(strings.ReplaceAll(name, "　", " "))
}

func validateName(v *validator, name string) {
	switch {
	case name == "":
		v.add("name", ReasonRequired)
	case utf8.RuneCountInString(name) > MaxNameLength:
		v.add("name", ReasonTooLong)
	}
}

// validateEmail は形式を検証する。小文字への変換は呼び出し側が行う。
func validateEmail(v *validator, email string) {
	switch {
	case email == "":
		v.add("email", ReasonRequired)
		return
	case utf8.RuneCountInString(email) > MaxEmailLength:
		v.add("email", ReasonTooLong)
		return
	}

	addr, err := mail.ParseAddress(email)
	if err != nil || addr.Address != email {
		// err != nil は形式そのものが不正な場合。addr.Address != email は
		// 「山田 <a@example.com>」のような表示名付きを弾くための判定。
		v.add("email", ReasonInvalidFormat)
		return
	}

	// ParseAddress は a@b のようにドットを含まないドメインも通すため、別途確認する。
	at := strings.LastIndex(email, "@")
	if at < 0 || !strings.Contains(email[at+1:], ".") {
		v.add("email", ReasonInvalidFormat)
	}
}

// validatePassword は、使える文字と長さを検証する（ADR 0008）。field は不正を
// 記録する項目名（登録・リセットでは password、本人による変更では new_password）。
//
// 判定の順序は Flutter 側の validateUserForm と揃える。欄ごとに 1 つの理由しか
// 表示しないため、順序が違うと同じ入力に別のエラーが出る。文字種を長さより先に
// 見るのは、日本語を数文字入力した利用者に「8 文字以上」ではなく「半角英数字と
// 記号で」と伝えるためである。
func validatePassword(v *validator, field, password string) {
	switch {
	case password == "":
		v.add(field, ReasonRequired)
	case !isASCIIGraphic(password):
		v.add(field, ReasonInvalidFormat)
	case utf8.RuneCountInString(password) < MinPasswordLength:
		v.add(field, ReasonTooShort)
	case utf8.RuneCountInString(password) > MaxPasswordLength:
		v.add(field, ReasonTooLong)
	}
}

// isASCIIGraphic は、文字列が ASCII の印字可能文字（U+0021〜U+007E）だけで
// できているかを返す。スペース（U+0020）は含まない。前後に付いても見えず、
// 入力ミスに気付けないためである。
func isASCIIGraphic(s string) bool {
	for _, r := range s {
		if r < 0x21 || r > 0x7E {
			return false
		}
	}
	return true
}
