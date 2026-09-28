package service

import (
	"context"
	"errors"
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"

	"backend/internal/model"
	"backend/internal/repository"
)

// fakeUserRepository は UserRepository の手書きのフェイク。
//
// service 層のテストは DB を必要としないため、モックライブラリも実 DB も
// 使わずにこれで差し替える（ADR 0003）。
type fakeUserRepository struct {
	users  []model.User
	nextID int64

	// Create に渡された引数。ハッシュ化や整形の結果を検証するために記録する。
	lastCreateName  string
	lastCreateEmail string
	lastCreateHash  string

	// UpdatePassword の呼び出し回数と、残すよう指示されたセッション。
	updatePasswordCalls int
	lastKeepSessionHash []byte
}

func newFakeRepo(users ...model.User) *fakeUserRepository {
	f := &fakeUserRepository{nextID: 1}
	for _, u := range users {
		if u.ID >= f.nextID {
			f.nextID = u.ID + 1
		}
		f.users = append(f.users, u)
	}
	return f
}

func (f *fakeUserRepository) index(id int64, includeDeleted bool) int {
	for i, u := range f.users {
		if u.ID == id && (includeDeleted || u.DeletedAt == nil) {
			return i
		}
	}
	return -1
}

func (f *fakeUserRepository) List(_ context.Context, includeDeleted bool, limit, offset int) ([]model.User, error) {
	var got []model.User
	for _, u := range f.users {
		if includeDeleted || u.DeletedAt == nil {
			got = append(got, u)
		}
	}
	if offset >= len(got) {
		return nil, nil
	}
	end := min(offset+limit, len(got))
	return got[offset:end], nil
}

func (f *fakeUserRepository) Count(_ context.Context, includeDeleted bool) (int, error) {
	n := 0
	for _, u := range f.users {
		if includeDeleted || u.DeletedAt == nil {
			n++
		}
	}
	return n, nil
}

func (f *fakeUserRepository) FindByID(_ context.Context, id int64, includeDeleted bool) (model.User, error) {
	if i := f.index(id, includeDeleted); i >= 0 {
		return f.users[i], nil
	}
	return model.User{}, repository.ErrNotFound
}

func (f *fakeUserRepository) FindByEmail(_ context.Context, email string) (model.User, error) {
	for _, u := range f.users {
		if u.Email == email {
			return u, nil
		}
	}
	return model.User{}, repository.ErrNotFound
}

func (f *fakeUserRepository) Create(_ context.Context, name, email, passwordHash string) (model.User, error) {
	f.lastCreateName, f.lastCreateEmail, f.lastCreateHash = name, email, passwordHash

	u := model.User{ID: f.nextID, Name: name, Email: email, PasswordHash: passwordHash}
	f.nextID++
	f.users = append(f.users, u)
	return u, nil
}

func (f *fakeUserRepository) Update(_ context.Context, id int64, name, email string) (model.User, error) {
	i := f.index(id, false)
	if i < 0 {
		return model.User{}, repository.ErrNotFound
	}
	f.users[i].Name, f.users[i].Email = name, email
	return f.users[i], nil
}

// UpdatePassword は、実際の SQL ではセッションも削除するが、フェイクでは
// どのセッションを残すよう指示されたかを記録するだけにする（削除そのものは
// repository 層のテストで確かめる）。
func (f *fakeUserRepository) UpdatePassword(_ context.Context, id int64, passwordHash string, keepSessionHash []byte) (model.User, error) {
	i := f.index(id, false)
	if i < 0 {
		return model.User{}, repository.ErrNotFound
	}
	f.users[i].PasswordHash = passwordHash
	f.updatePasswordCalls++
	f.lastKeepSessionHash = keepSessionHash
	return f.users[i], nil
}

func (f *fakeUserRepository) Unlock(_ context.Context, id int64) (model.User, error) {
	i := f.index(id, false)
	if i < 0 {
		return model.User{}, repository.ErrNotFound
	}
	f.users[i].IsLocked = false
	f.users[i].FailedLoginAttempts = 0
	return f.users[i], nil
}

func (f *fakeUserRepository) SoftDelete(_ context.Context, id int64) (model.User, error) {
	i := f.index(id, false)
	if i < 0 {
		return model.User{}, repository.ErrNotFound
	}
	now := fixedTime()
	f.users[i].DeletedAt = &now
	return f.users[i], nil
}

// newService はテスト用の UserService を作る。
// bcrypt のコストを最小にしているのは、既定値（10）だと 1 回あたり 50〜100
// ミリ秒かかり、テストの実行時間に直結するため（ADR 0003）。
func newService(repo UserRepository) *UserService {
	return NewUserService(repo, bcrypt.MinCost)
}

// issuesOf は err から検証エラーの内訳を取り出す。
func issuesOf(t *testing.T, err error) []Issue {
	t.Helper()
	var ve *ValidationError
	if !errors.As(err, &ve) {
		t.Fatalf("*ValidationError ではないエラーが返った: %v", err)
	}
	return ve.Issues
}

func TestUserServiceCreateNormalizesInput(t *testing.T) {
	repo := newFakeRepo()
	created, err := newService(repo).Create(context.Background(),
		"　山田　太郎　", "  Yamada@Example.COM  ", "password123")
	if err != nil {
		t.Fatalf("登録に失敗した: %v", err)
	}

	// 前後の全角空白は削除され、姓名間の全角空白は半角になる。
	if created.Name != "山田 太郎" {
		t.Errorf("name の整形結果が異なる: %q", created.Name)
	}
	// メールアドレスは小文字で保存される（DB の UNIQUE は大文字小文字を区別するため）。
	if created.Email != "yamada@example.com" {
		t.Errorf("email が小文字になっていない: %q", created.Email)
	}
	// パスワードは平文で保存されない。
	if repo.lastCreateHash == "password123" {
		t.Fatal("パスワードが平文のまま渡されている")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(repo.lastCreateHash), []byte("password123")); err != nil {
		t.Errorf("保存されたハッシュが元のパスワードと一致しない: %v", err)
	}
}

func TestUserServiceCreateValidation(t *testing.T) {
	const validName, validEmail, validPassword = "山田 太郎", "yamada@example.com", "password123"

	tests := []struct {
		title    string
		name     string
		email    string
		password string
		want     []Issue
	}{
		{"すべて正しい", validName, validEmail, validPassword, nil},
		{"name が空", "", validEmail, validPassword,
			[]Issue{{"name", ReasonRequired}}},
		{"name が空白のみ", "　 　", validEmail, validPassword,
			[]Issue{{"name", ReasonRequired}}},
		{"name が 255 文字", strings.Repeat("あ", 255), validEmail, validPassword, nil},
		{"name が 256 文字", strings.Repeat("あ", 256), validEmail, validPassword,
			[]Issue{{"name", ReasonTooLong}}},
		{"email が空", validName, "", validPassword,
			[]Issue{{"email", ReasonRequired}}},
		{"email の形式が不正", validName, "not-an-email", validPassword,
			[]Issue{{"email", ReasonInvalidFormat}}},
		{"email のドメインにドットがない", validName, "a@b", validPassword,
			[]Issue{{"email", ReasonInvalidFormat}}},
		{"email が表示名付き", validName, "山田 <a@example.com>", validPassword,
			[]Issue{{"email", ReasonInvalidFormat}}},
		{"password が空", validName, validEmail, "",
			[]Issue{{"password", ReasonRequired}}},
		{"password が 7 文字", validName, validEmail, "1234567",
			[]Issue{{"password", ReasonTooShort}}},
		{"password が 8 文字", validName, validEmail, "12345678", nil},
		{"password が記号のみ 8 文字", validName, validEmail, `!"#$%&'(`, nil},
		{"password が 72 文字", validName, validEmail, strings.Repeat("a", 72), nil},
		{"password が 73 文字", validName, validEmail, strings.Repeat("a", 73),
			[]Issue{{"password", ReasonTooLong}}},
		{"password に日本語を含む", validName, validEmail, "パスワード1234",
			[]Issue{{"password", ReasonInvalidFormat}}},
		{"password にスペースを含む", validName, validEmail, "pass word123",
			[]Issue{{"password", ReasonInvalidFormat}}},
		{"password に全角記号を含む", validName, validEmail, "password１２３",
			[]Issue{{"password", ReasonInvalidFormat}}},
		// 文字種を長さより先に判定するため、短くても文字種のエラーになる
		{"password が日本語 3 文字", validName, validEmail, "あいう",
			[]Issue{{"password", ReasonInvalidFormat}}},
		{"複数の項目が同時に不正", "", "a@b", "123",
			[]Issue{{"name", ReasonRequired}, {"email", ReasonInvalidFormat}, {"password", ReasonTooShort}}},
	}

	for _, tt := range tests {
		t.Run(tt.title, func(t *testing.T) {
			_, err := newService(newFakeRepo()).Create(context.Background(), tt.name, tt.email, tt.password)
			if tt.want == nil {
				if err != nil {
					t.Fatalf("エラーにならないはずが返った: %v", err)
				}
				return
			}

			got := issuesOf(t, err)
			if len(got) != len(tt.want) {
				t.Fatalf("Issue の件数が異なる: got %v, want %v", got, tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Errorf("Issue[%d] が異なる: got %v, want %v", i, got[i], tt.want[i])
				}
			}
		})
	}
}

func TestUserServiceCreateEmailConflict(t *testing.T) {
	deletedAt := fixedTime()
	repo := newFakeRepo(
		model.User{ID: 1, Name: "生存 ユーザー", Email: "alive@example.com"},
		model.User{ID: 2, Name: "削除済み ユーザー", Email: "deleted@example.com", DeletedAt: &deletedAt},
	)
	svc := newService(repo)

	// 生存しているユーザーとの衝突。
	if _, err := svc.Create(context.Background(), "別人", "alive@example.com", "password123"); !errors.Is(err, ErrEmailAlreadyExists) {
		t.Errorf("ErrEmailAlreadyExists が返らなかった: %v", err)
	}

	// 削除済みのユーザーとの衝突。復帰はさせず、別のエラーで区別する（ADR 0004）。
	if _, err := svc.Create(context.Background(), "別人", "deleted@example.com", "password123"); !errors.Is(err, ErrEmailBelongsToDeletedUser) {
		t.Errorf("ErrEmailBelongsToDeletedUser が返らなかった: %v", err)
	}

	// 大文字で送られても、小文字化した結果で重複と判定される。
	if _, err := svc.Create(context.Background(), "別人", "Alive@Example.com", "password123"); !errors.Is(err, ErrEmailAlreadyExists) {
		t.Errorf("大文字のアドレスが重複と判定されなかった: %v", err)
	}
}

func TestUserServiceUpdate(t *testing.T) {
	deletedAt := fixedTime()

	t.Run("自分自身と同じメールアドレスは重複扱いしない", func(t *testing.T) {
		repo := newFakeRepo(model.User{ID: 1, Name: "山田 太郎", Email: "yamada@example.com"})

		updated, err := newService(repo).Update(context.Background(), 1, "山田 次郎", "yamada@example.com")
		if err != nil {
			t.Fatalf("更新に失敗した: %v", err)
		}
		if updated.Name != "山田 次郎" {
			t.Errorf("name が更新されていない: %q", updated.Name)
		}
	})

	t.Run("他のユーザーのメールアドレスへは変更できない", func(t *testing.T) {
		repo := newFakeRepo(
			model.User{ID: 1, Name: "山田 太郎", Email: "yamada@example.com"},
			model.User{ID: 2, Name: "鈴木 花子", Email: "suzuki@example.com"},
		)

		_, err := newService(repo).Update(context.Background(), 1, "山田 太郎", "suzuki@example.com")
		if !errors.Is(err, ErrEmailAlreadyExists) {
			t.Errorf("ErrEmailAlreadyExists が返らなかった: %v", err)
		}
	})

	t.Run("削除済みのユーザーは更新できない", func(t *testing.T) {
		repo := newFakeRepo(model.User{ID: 1, Name: "山田 太郎", Email: "yamada@example.com", DeletedAt: &deletedAt})

		_, err := newService(repo).Update(context.Background(), 1, "山田 次郎", "yamada@example.com")
		if !errors.Is(err, ErrUserNotFound) {
			t.Errorf("ErrUserNotFound が返らなかった: %v", err)
		}
	})
}

func TestUserServiceResetPassword(t *testing.T) {
	repo := newFakeRepo(model.User{ID: 1, Name: "山田 太郎", Email: "yamada@example.com"})
	svc := newService(repo)

	t.Run("検証規則は登録時と同じ", func(t *testing.T) {
		_, err := svc.ResetPassword(context.Background(), 1, "1234567")
		got := issuesOf(t, err)
		if len(got) != 1 || got[0] != (Issue{"password", ReasonTooShort}) {
			t.Errorf("想定と異なる内訳: %v", got)
		}
	})

	t.Run("ハッシュ化して保存する", func(t *testing.T) {
		updated, err := svc.ResetPassword(context.Background(), 1, "newpassword")
		if err != nil {
			t.Fatalf("リセットに失敗した: %v", err)
		}
		if err := bcrypt.CompareHashAndPassword([]byte(updated.PasswordHash), []byte("newpassword")); err != nil {
			t.Errorf("保存されたハッシュが新しいパスワードと一致しない: %v", err)
		}
		// 管理者によるリセットでは、残すセッションを指定しない（全セッションを削除する。ADR 0012）。
		if repo.lastKeepSessionHash != nil {
			t.Errorf("残すセッションを指定してはいけない: %x", repo.lastKeepSessionHash)
		}
	})

	t.Run("存在しないユーザー", func(t *testing.T) {
		if _, err := svc.ResetPassword(context.Background(), 999, "password123"); !errors.Is(err, ErrUserNotFound) {
			t.Errorf("ErrUserNotFound が返らなかった: %v", err)
		}
	})
}

func TestUserServiceUnlock(t *testing.T) {
	lockedAt := fixedTime()
	repo := newFakeRepo(
		model.User{ID: 1, Name: "山田 太郎", Email: "yamada@example.com",
			IsLocked: true, LockedAt: &lockedAt, FailedLoginAttempts: 5},
	)
	svc := newService(repo)

	unlocked, err := svc.Unlock(context.Background(), 1)
	if err != nil {
		t.Fatalf("解除に失敗した: %v", err)
	}
	if unlocked.IsLocked || unlocked.FailedLoginAttempts != 0 {
		t.Errorf("解除されていない: is_locked=%v, failed_login_attempts=%d", unlocked.IsLocked, unlocked.FailedLoginAttempts)
	}
	// locked_at は「最後にロックがかかった日時」として残す。
	if unlocked.LockedAt == nil {
		t.Error("locked_at が消えている")
	}

	// ロックされていないユーザーに実行してもエラーにしない。
	if _, err := svc.Unlock(context.Background(), 1); err != nil {
		t.Errorf("2 回目の解除でエラーになった: %v", err)
	}
}

func TestUserServiceDelete(t *testing.T) {
	repo := newFakeRepo(model.User{ID: 1, Name: "山田 太郎", Email: "yamada@example.com"})
	svc := newService(repo)

	deleted, err := svc.Delete(context.Background(), 1)
	if err != nil {
		t.Fatalf("削除に失敗した: %v", err)
	}
	if deleted.DeletedAt == nil {
		t.Error("deleted_at が入っていない")
	}

	// 2 回目は対象が見つからない（更新系は生存している行のみを対象とする）。
	if _, err := svc.Delete(context.Background(), 1); !errors.Is(err, ErrUserNotFound) {
		t.Errorf("ErrUserNotFound が返らなかった: %v", err)
	}
}

func TestUserServiceListCountsWithSameCondition(t *testing.T) {
	deletedAt := fixedTime()
	repo := newFakeRepo(
		model.User{ID: 1, Email: "a@example.com"},
		model.User{ID: 2, Email: "b@example.com", DeletedAt: &deletedAt},
		model.User{ID: 3, Email: "c@example.com"},
	)
	svc := newService(repo)

	users, total, err := svc.List(context.Background(), 1, 20, false)
	if err != nil {
		t.Fatalf("一覧の取得に失敗した: %v", err)
	}
	if len(users) != 2 || total != 2 {
		t.Errorf("削除済みが除かれていない: len=%d, total=%d", len(users), total)
	}

	users, total, err = svc.List(context.Background(), 1, 20, true)
	if err != nil {
		t.Fatalf("一覧の取得に失敗した: %v", err)
	}
	if len(users) != 3 || total != 3 {
		t.Errorf("削除済みが含まれていない: len=%d, total=%d", len(users), total)
	}

	// 範囲外のページは空になる（エラーにはしない）。
	users, total, err = svc.List(context.Background(), 99, 20, false)
	if err != nil {
		t.Fatalf("一覧の取得に失敗した: %v", err)
	}
	if len(users) != 0 || total != 2 {
		t.Errorf("範囲外のページの扱いが想定と異なる: len=%d, total=%d", len(users), total)
	}
}
