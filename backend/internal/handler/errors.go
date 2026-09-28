package handler

import (
	"errors"
	"fmt"
	"log"
	"net/http"

	"backend/internal/service"
)

// writeServiceError は service が返したエラーを HTTP のレスポンスへ変換する。
//
// service は「何が起きたか」だけを返すため、ステータスコード・エラーコード・
// 利用者に見せる日本語の文言はこのファイルだけが持つ（ADR 0004）。
func writeServiceError(w http.ResponseWriter, err error) {
	var ve *service.ValidationError

	switch {
	case errors.As(err, &ve):
		writeError(w, http.StatusBadRequest, "validation_error",
			"入力内容に誤りがあります。", fieldErrorsOf(ve))

	case errors.Is(err, service.ErrUserNotFound):
		writeError(w, http.StatusNotFound, "not_found",
			"ユーザーが見つかりません。", nil)

	case errors.Is(err, service.ErrEmailAlreadyExists):
		writeError(w, http.StatusConflict, "email_already_exists",
			"このメールアドレスは既に登録されています", nil)

	case errors.Is(err, service.ErrEmailBelongsToDeletedUser):
		writeError(w, http.StatusConflict, "email_belongs_to_deleted_user",
			"このメールアドレスは削除済みのユーザーが使用しているため登録できません", nil)

	case errors.Is(err, service.ErrInvalidCredentials):
		writeError(w, http.StatusUnauthorized, "invalid_credentials",
			"メールアドレスまたはパスワードが正しくありません。", nil)

	case errors.Is(err, service.ErrAccountLocked):
		writeError(w, http.StatusForbidden, "account_locked",
			"アカウントがロックされています。管理者に解除を依頼してください。", nil)

	case errors.Is(err, service.ErrUnauthenticated):
		writeUnauthenticated(w)

	default:
		// 原因はサーバーのログにだけ出す。DB の接続情報やテーブル構造が
		// 外部に漏れないよう、レスポンスには含めない。
		log.Printf("想定外のエラーが発生しました: %v", err)
		writeError(w, http.StatusInternalServerError, "internal_error",
			"サーバー内部でエラーが発生しました。", nil)
	}
}

func fieldErrorsOf(ve *service.ValidationError) []fieldError {
	fields := make([]fieldError, 0, len(ve.Issues))
	for _, i := range ve.Issues {
		fields = append(fields, fieldError{Field: i.Field, Message: fieldMessage(i)})
	}
	return fields
}

// fieldMessage は、どの項目がどういう理由で不正かを日本語の文言にする。
func fieldMessage(i service.Issue) string {
	switch i.Field {
	case "name":
		switch i.Reason {
		case service.ReasonRequired:
			return "名前を入力してください"
		case service.ReasonTooLong:
			return fmt.Sprintf("名前は %d 文字以内で入力してください", service.MaxNameLength)
		}

	case "email":
		switch i.Reason {
		case service.ReasonRequired:
			return "メールアドレスを入力してください"
		case service.ReasonTooLong:
			return fmt.Sprintf("メールアドレスは %d 文字以内で入力してください", service.MaxEmailLength)
		case service.ReasonInvalidFormat:
			return "メールアドレスの形式が正しくありません"
		}

	case "password":
		switch i.Reason {
		case service.ReasonRequired:
			return "パスワードを入力してください"
		case service.ReasonTooShort, service.ReasonTooLong:
			// 短すぎ・長すぎのどちらも、利用者が知りたいのは許される範囲そのもの
			// であるため、同じ文言で両端を示す。
			return fmt.Sprintf("パスワードは %d 文字以上 %d 文字以内で入力してください",
				service.MinPasswordLength, service.MaxPasswordLength)
		case service.ReasonInvalidFormat:
			return "パスワードは半角英数字と記号（スペースを除く）で入力してください"
		}

	case "current_password":
		switch i.Reason {
		case service.ReasonRequired:
			return "現在のパスワードを入力してください"
		case service.ReasonIncorrect:
			return "現在のパスワードが正しくありません"
		}

	case "new_password":
		switch i.Reason {
		case service.ReasonRequired:
			return "新しいパスワードを入力してください"
		case service.ReasonTooShort, service.ReasonTooLong:
			return fmt.Sprintf("パスワードは %d 文字以上 %d 文字以内で入力してください",
				service.MinPasswordLength, service.MaxPasswordLength)
		case service.ReasonInvalidFormat:
			return "パスワードは半角英数字と記号（スペースを除く）で入力してください"
		case service.ReasonSameAsCurrent:
			return "現在のパスワードと同じパスワードは設定できません"
		}

	case "page":
		switch i.Reason {
		case service.ReasonInvalidFormat:
			return "page は整数で指定してください"
		case service.ReasonOutOfRange:
			return "page は 1 以上で指定してください"
		}

	case "per_page":
		switch i.Reason {
		case service.ReasonInvalidFormat:
			return "per_page は整数で指定してください"
		case service.ReasonOutOfRange:
			return fmt.Sprintf("per_page は 1 以上 %d 以下で指定してください", service.MaxPerPage)
		}

	case "include_deleted":
		if i.Reason == service.ReasonInvalidFormat {
			return "include_deleted は true または false で指定してください"
		}
	}

	// 上記で拾えなかった組み合わせ。文言を足し忘れても情報が失われないようにする。
	return fmt.Sprintf("%s の値が正しくありません（%s）", i.Field, i.Reason)
}
