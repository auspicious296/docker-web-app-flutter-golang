package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"backend/internal/service"
)

// UserHandler はユーザー管理 API のハンドラ。
type UserHandler struct {
	svc *service.UserService
}

func NewUserHandler(svc *service.UserService) *UserHandler {
	return &UserHandler{svc: svc}
}

// Register はルートを登録する。
//
// Go 1.22 以降の ServeMux は、メソッドとパスパラメータをパターンで書ける。
func (h *UserHandler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/users", h.list)
	mux.HandleFunc("POST /api/users", h.create)
	mux.HandleFunc("GET /api/users/{id}", h.get)
	mux.HandleFunc("PUT /api/users/{id}", h.update)
	mux.HandleFunc("DELETE /api/users/{id}", h.delete)
	mux.HandleFunc("PUT /api/users/{id}/password", h.resetPassword)
	mux.HandleFunc("POST /api/users/{id}/unlock", h.unlock)
}

func (h *UserHandler) list(w http.ResponseWriter, r *http.Request) {
	page, perPage, includeDeleted, err := parseListQuery(r)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	users, total, err := h.svc.List(r.Context(), page, perPage, includeDeleted)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newListResponse(users, page, perPage, total))
}

func (h *UserHandler) get(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	includeDeleted, err := parseIncludeDeleted(r)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	u, err := h.svc.Get(r.Context(), id, includeDeleted)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newUserResponse(u))
}

func (h *UserHandler) create(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name     string `json:"name"`
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}

	created, err := h.svc.Create(r.Context(), req.Name, req.Email, req.Password)
	if err != nil {
		writeServiceError(w, err)
		return
	}

	// 201 では作成されたリソースの URI を Location で示す。
	w.Header().Set("Location", "/api/users/"+strconv.FormatInt(created.ID, 10))
	writeJSON(w, http.StatusCreated, newUserResponse(created))
}

func (h *UserHandler) update(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	var req struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}

	updated, err := h.svc.Update(r.Context(), id, req.Name, req.Email)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newUserResponse(updated))
}

func (h *UserHandler) resetPassword(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	var req struct {
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &req) {
		return
	}

	updated, err := h.svc.ResetPassword(r.Context(), id, req.Password)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newUserResponse(updated))
}

func (h *UserHandler) unlock(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	updated, err := h.svc.Unlock(r.Context(), id)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newUserResponse(updated))
}

func (h *UserHandler) delete(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}

	deleted, err := h.svc.Delete(r.Context(), id)
	if err != nil {
		writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, newUserResponse(deleted))
}

// pathID は {id} を取り出す。整数でなければ 400 を返して false を返す。
func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_id",
			"ユーザー ID は整数で指定してください。", nil)
		return 0, false
	}
	return id, true
}

// decodeJSON はリクエストボディを読む。
//
// 未知のフィールドが含まれていても無視する（DisallowUnknownFields は使わない）。
func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json",
			"リクエストの形式が正しくありません。", nil)
		return false
	}
	return true
}

// parseListQuery は page / per_page / include_deleted を読む。
//
// 不正な値は既定値へ丸めず、検証エラーとしてまとめて返す（ADR 0004）。
func parseListQuery(r *http.Request) (page, perPage int, includeDeleted bool, err error) {
	q := r.URL.Query()
	page, perPage = service.DefaultPage, service.DefaultPerPage

	var issues []service.Issue

	if s := q.Get("page"); s != "" {
		n, convErr := strconv.Atoi(s)
		switch {
		case convErr != nil:
			issues = append(issues, service.Issue{Field: "page", Reason: service.ReasonInvalidFormat})
		case n < 1:
			issues = append(issues, service.Issue{Field: "page", Reason: service.ReasonOutOfRange})
		default:
			page = n
		}
	}

	if s := q.Get("per_page"); s != "" {
		n, convErr := strconv.Atoi(s)
		switch {
		case convErr != nil:
			issues = append(issues, service.Issue{Field: "per_page", Reason: service.ReasonInvalidFormat})
		case n < 1 || n > service.MaxPerPage:
			issues = append(issues, service.Issue{Field: "per_page", Reason: service.ReasonOutOfRange})
		default:
			perPage = n
		}
	}

	if s := q.Get("include_deleted"); s != "" {
		b, convErr := strconv.ParseBool(s)
		if convErr != nil {
			issues = append(issues, service.Issue{Field: "include_deleted", Reason: service.ReasonInvalidFormat})
		} else {
			includeDeleted = b
		}
	}

	if len(issues) > 0 {
		return 0, 0, false, service.NewValidationError(issues...)
	}
	return page, perPage, includeDeleted, nil
}

// parseIncludeDeleted は 1 件取得での include_deleted を読む。
func parseIncludeDeleted(r *http.Request) (bool, error) {
	s := r.URL.Query().Get("include_deleted")
	if s == "" {
		return false, nil
	}

	b, err := strconv.ParseBool(s)
	if err != nil {
		return false, service.NewValidationError(
			service.Issue{Field: "include_deleted", Reason: service.ReasonInvalidFormat})
	}
	return b, nil
}
