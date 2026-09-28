package handler

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
)

// JSONErrorFallback は、ServeMux が自動で返す 404 / 405 の本文を JSON に
// 差し替えるラッパー。
//
// 標準の ServeMux は、登録していないパスには「404 page not found」、パスは
// 一致するがメソッドが違う場合には「Method Not Allowed」を、いずれも
// プレーンテキストで返す。これを放置すると /api/ 配下の応答形式が揃わず、
// Flutter 側が「失敗時は必ず JSON が返る」前提で書けなくなる（ADR 0004）。
//
// ステータスコードは変えず、本文だけを差し替える。405 のときに ServeMux が
// 付ける Allow ヘッダーもそのまま残る。
func JSONErrorFallback(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(&fallbackWriter{ResponseWriter: w, method: r.Method}, r)
	})
}

type fallbackWriter struct {
	http.ResponseWriter
	method      string
	wroteHeader bool
	replaced    bool
}

func (w *fallbackWriter) WriteHeader(status int) {
	if w.wroteHeader {
		return
	}
	w.wroteHeader = true

	// 自前のハンドラが返す 404（ユーザーが見つからない）は既に JSON なので
	// 触らない。ServeMux が返す 404 / 405 は http.Error を経由しており
	// Content-Type が text/plain になっているため、これで見分けられる。
	alreadyJSON := strings.HasPrefix(w.Header().Get("Content-Type"), "application/json")
	if alreadyJSON || (status != http.StatusNotFound && status != http.StatusMethodNotAllowed) {
		w.ResponseWriter.WriteHeader(status)
		return
	}

	w.replaced = true

	code, message := "not_found", "指定されたパスは存在しません。"
	if status == http.StatusMethodNotAllowed {
		code = "method_not_allowed"
		message = fmt.Sprintf("このパスでは %s は使用できません。", w.method)
	}

	w.Header().Set("Content-Type", contentTypeJSON)
	w.ResponseWriter.WriteHeader(status)

	body := errorResponse{Error: errorBody{Code: code, Message: message}}
	if err := json.NewEncoder(w.ResponseWriter).Encode(body); err != nil {
		log.Printf("レスポンスの書き込みに失敗しました: %v", err)
	}
}

// Write は、本文を差し替えた場合に ServeMux が書こうとしたプレーンテキストを捨てる。
func (w *fallbackWriter) Write(b []byte) (int, error) {
	if w.replaced {
		return len(b), nil
	}
	if !w.wroteHeader {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(b)
}
