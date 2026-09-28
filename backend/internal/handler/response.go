// Package handler は HTTP リクエストの受け口。JSON の読み書きと、service が
// 返したエラーを HTTP のステータスコード・エラーコード・日本語の文言へ
// 変換することを担う（ADR 0004）。
package handler

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"backend/internal/model"
)

const contentTypeJSON = "application/json; charset=utf-8"

// userResponse は API が返すユーザー 1 件。
//
// password_hash は含めない。キーは DB のカラム名と揃えた snake_case、日時は
// RFC 3339（time.Time の既定の JSON 表現）。
type userResponse struct {
	ID                  int64      `json:"id"`
	Name                string     `json:"name"`
	Email               string     `json:"email"`
	CreatedAt           time.Time  `json:"created_at"`
	UpdatedAt           time.Time  `json:"updated_at"`
	DeletedAt           *time.Time `json:"deleted_at"`
	IsLocked            bool       `json:"is_locked"`
	LockedAt            *time.Time `json:"locked_at"`
	FailedLoginAttempts int        `json:"failed_login_attempts"`
	LastLoginAt         *time.Time `json:"last_login_at"`
}

func newUserResponse(u model.User) userResponse {
	return userResponse{
		ID:                  u.ID,
		Name:                u.Name,
		Email:               u.Email,
		CreatedAt:           u.CreatedAt,
		UpdatedAt:           u.UpdatedAt,
		DeletedAt:           u.DeletedAt,
		IsLocked:            u.IsLocked,
		LockedAt:            u.LockedAt,
		FailedLoginAttempts: u.FailedLoginAttempts,
		LastLoginAt:         u.LastLoginAt,
	}
}

// listResponse は一覧のレスポンス。ページングのメタ情報を足せるよう、裸の
// 配列ではなくオブジェクトで包む（ADR 0004）。
type listResponse struct {
	Users   []userResponse `json:"users"`
	Page    int            `json:"page"`
	PerPage int            `json:"per_page"`
	Total   int            `json:"total"`
}

func newListResponse(users []model.User, page, perPage, total int) listResponse {
	// 0 件のときに null ではなく [] を返すため、明示的に確保する。
	list := make([]userResponse, 0, len(users))
	for _, u := range users {
		list = append(list, newUserResponse(u))
	}
	return listResponse{Users: list, Page: page, PerPage: perPage, Total: total}
}

// 失敗時のレスポンス。fields は検証エラーのときだけ付ける。
type errorResponse struct {
	Error errorBody `json:"error"`
}

type errorBody struct {
	Code    string       `json:"code"`
	Message string       `json:"message"`
	Fields  []fieldError `json:"fields,omitempty"`
}

type fieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", contentTypeJSON)
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("レスポンスの書き込みに失敗しました: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, code, message string, fields []fieldError) {
	writeJSON(w, status, errorResponse{Error: errorBody{Code: code, Message: message, Fields: fields}})
}
