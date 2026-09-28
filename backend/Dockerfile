# ---------------------------------------------
# ステージ 1：ビルド用
# ---------------------------------------------
FROM golang:1.27.1-alpine AS build

WORKDIR /src

# 依存関係の定義（go.sum は外部ライブラリ追加後に作られる）を先にコピーし、ソース変更時もダウンロード結果のキャッシュを再利用する
COPY go.mod go.sum* ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o /out/api ./cmd/api

# ---------------------------------------------
# ステージ 2：実行用
# ---------------------------------------------
FROM alpine:3.24.2

COPY --from=build /out/api /usr/local/bin/api

EXPOSE 8080

CMD ["api"]
