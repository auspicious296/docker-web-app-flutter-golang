package repository

import (
	"context"
	"errors"
	"testing"

	"backend/internal/model"
)

func TestFindActiveByEmailExcludesDeleted(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	id := createUser(t, "a@example.com")

	if u, err := repo.FindActiveByEmail(context.Background(), "a@example.com"); err != nil || u.ID != id {
		t.Fatalf("削除されていないユーザーが見つからない: %v", err)
	}
	if _, err := repo.SoftDelete(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.FindActiveByEmail(context.Background(), "a@example.com"); !errors.Is(err, ErrNotFound) {
		t.Errorf("削除済みのユーザーは ErrNotFound: %v", err)
	}
}

func TestRecordLoginFailureLocksOnFifth(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	ctx := context.Background()
	id := createUser(t, "a@example.com")
	before, _ := repo.FindByID(ctx, id, false)

	for n := 1; n <= 4; n++ {
		locked, err := repo.RecordLoginFailure(ctx, id, 5)
		if err != nil || locked {
			t.Fatalf("%d 回目でロックされた: %v", n, err)
		}
	}
	u, _ := repo.FindByID(ctx, id, false)
	if u.FailedLoginAttempts != 4 || u.IsLocked || u.LockedAt != nil {
		t.Errorf("4 回目まではロックしない: %+v", u)
	}
	if !u.UpdatedAt.Equal(before.UpdatedAt) {
		t.Error("回数の加算では updated_at を更新しない")
	}

	locked, err := repo.RecordLoginFailure(ctx, id, 5)
	if err != nil || !locked {
		t.Fatalf("5 回目でロックする: %v", err)
	}
	u, _ = repo.FindByID(ctx, id, false)
	if u.FailedLoginAttempts != 5 || !u.IsLocked || u.LockedAt == nil || !u.UpdatedAt.After(before.UpdatedAt) {
		t.Errorf("ロックの記録が異なる（ロックしたときは updated_at も更新する）: %+v", u)
	}

	if _, err := repo.RecordLoginFailure(ctx, id, 5); !errors.Is(err, ErrNotFound) {
		t.Errorf("ロック中は加算せず ErrNotFound: %v", err)
	}
}

func TestResetLoginFailures(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	ctx := context.Background()
	id := createUser(t, "a@example.com")
	repo.RecordLoginFailure(ctx, id, 5)
	before, _ := repo.FindByID(ctx, id, false)

	if err := repo.ResetLoginFailures(ctx, id); err != nil {
		t.Fatal(err)
	}
	u, _ := repo.FindByID(ctx, id, false)
	if u.FailedLoginAttempts != 0 || !u.UpdatedAt.Equal(before.UpdatedAt) {
		t.Errorf("0 に戻し、updated_at は更新しない: %+v", u)
	}
}

func TestRecordLoginSuccess(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	ctx := context.Background()
	id := createUser(t, "a@example.com")
	repo.RecordLoginFailure(ctx, id, 5)
	before, _ := repo.FindByID(ctx, id, false)
	if before.LastLoginAt != nil {
		t.Fatalf("一度もログインしていなければ NULL: %+v", before)
	}

	if err := repo.RecordLoginSuccess(ctx, id); err != nil {
		t.Fatal(err)
	}
	u, _ := repo.FindByID(ctx, id, false)
	if u.FailedLoginAttempts != 0 || u.LastLoginAt == nil || !u.UpdatedAt.Equal(before.UpdatedAt) {
		t.Errorf("0 に戻して最終ログイン日時を入れ、updated_at は更新しない: %+v", u)
	}
}

func TestRecordLoginSuccessIgnoresDeleted(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	ctx := context.Background()
	id := createUser(t, "a@example.com")
	if _, err := repo.SoftDelete(ctx, id); err != nil {
		t.Fatal(err)
	}

	if err := repo.RecordLoginSuccess(ctx, id); err != nil {
		t.Fatal(err)
	}
	u, _ := repo.FindByID(ctx, id, true)
	if u.LastLoginAt != nil {
		t.Errorf("削除済みには記録しない: %+v", u)
	}
}

func TestUpdatePasswordDeletesSessions(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	ctx := context.Background()
	id := createUser(t, "a@example.com")
	other := createUser(t, "b@example.com")
	current := createSession(t, "current", id, model.ClientWeb)
	another := createSession(t, "another", id, model.ClientMobile)
	othersSession := createSession(t, "others", other, model.ClientWeb)

	// 本人による変更：今のセッションだけを残す。
	u, err := repo.UpdatePassword(ctx, id, "new-hash", current)
	if err != nil || u.PasswordHash != "new-hash" {
		t.Fatalf("パスワードを更新できない: %v", err)
	}
	if !sessionExists(t, current) || sessionExists(t, another) || !sessionExists(t, othersSession) {
		t.Error("今のセッション以外の、本人のセッションだけを削除する")
	}

	// 管理者によるリセット：全セッションを削除する。
	if _, err := repo.UpdatePassword(ctx, id, "reset-hash", nil); err != nil {
		t.Fatal(err)
	}
	if sessionExists(t, current) || !sessionExists(t, othersSession) {
		t.Error("本人の全セッションを削除し、他人のセッションは残す")
	}
}

func TestSoftDeleteDeletesSessions(t *testing.T) {
	resetDB(t)
	repo := NewUserRepository(testPool)
	id := createUser(t, "a@example.com")
	other := createUser(t, "b@example.com")
	mine := createSession(t, "mine", id, model.ClientWeb)
	othersSession := createSession(t, "others", other, model.ClientWeb)

	if _, err := repo.SoftDelete(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	if sessionExists(t, mine) || !sessionExists(t, othersSession) {
		t.Error("削除したユーザーのセッションだけを削除する")
	}
}
