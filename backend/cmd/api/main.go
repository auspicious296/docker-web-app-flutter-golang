package main

import (
	"context"
	"log"
	"net/http"
	"time"

	// 実行イメージ（alpine）にはタイムゾーンのデータベースが含まれておらず、
	// TZ を設定しても Go が UTC にフォールバックしてしまう。これを import すると
	// データベースが実行ファイルに埋め込まれ、TZ: Asia/Tokyo が効くようになる。
	_ "time/tzdata"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"backend/internal/config"
	"backend/internal/handler"
	"backend/internal/model"
	"backend/internal/repository"
	"backend/internal/service"
)

// sessionCleanupInterval は、期限切れのセッションを削除する間隔（ADR 0012）。
const sessionCleanupInterval = time.Hour

func main() {
	// 必要な環境変数が 1 つでも未設定・不正なら、起動時に中止する。
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("設定を読み込めません:\n%v", err)
	}

	ctx := context.Background()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("DATABASE_URL の解析に失敗しました: %v", err)
	}
	defer pool.Close()

	// pgxpool.New はプールを用意するだけで、実際の接続はクエリを投げるまで
	// 行われない。設定の誤りや DB の未起動に起動の時点で気付けるよう、ここで
	// 1 度だけ疎通を確認する（稼働中の監視は行わない）。
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("DB に接続できません: %v", err)
	}
	log.Println("DB への接続を確認しました")

	userRepo := repository.NewUserRepository(pool)
	userService := service.NewUserService(userRepo, bcrypt.DefaultCost)
	userHandler := handler.NewUserHandler(userService)

	authService, err := service.NewAuthService(userRepo, repository.NewSessionRepository(pool), service.AuthConfig{
		// UserService と同じ値にする（ダミーのハッシュ値の照合時間を本物と揃えるため）。
		BcryptCost: bcrypt.DefaultCost,
		Timeouts: model.SessionTimeouts{
			WebIdle:        cfg.WebIdleTimeout,
			WebAbsolute:    cfg.WebAbsoluteTimeout,
			MobileIdle:     cfg.MobileIdleTimeout,
			MobileAbsolute: cfg.MobileAbsoluteTimeout,
		},
		CSRFSigningKey: cfg.CSRFSigningKey,
	})
	if err != nil {
		log.Fatalf("認証の準備に失敗しました: %v", err)
	}
	authHandler := handler.NewAuthHandler(authService, cfg.AllowedOrigin)

	go cleanupExpiredSessions(authService)

	mux := http.NewServeMux()

	// 動作確認用のエンドポイント
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	userHandler.Register(mux)
	authHandler.Register(mux)

	log.Println("API サーバーを :8080 で起動します")
	// ServeMux が自動で返す 404 / 405 も JSON に揃えるため、ラッパーを 1 枚挟む。
	log.Fatal(http.ListenAndServe(":8080", handler.JSONErrorFallback(mux)))
}

// cleanupExpiredSessions は、期限切れのセッションを、起動直後に 1 回、その後は
// 1 時間ごとに削除する。失敗してもログに残すだけで止めず、次の回に再実行する
// （ADR 0012）。
func cleanupExpiredSessions(svc *service.AuthService) {
	run := func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
		defer cancel()

		n, err := svc.DeleteExpiredSessions(ctx)
		if err != nil {
			log.Printf("期限切れのセッションの削除に失敗しました（次の回に再実行します）: %v", err)
			return
		}
		if n > 0 {
			log.Printf("期限切れのセッションを %d 件削除しました", n)
		}
	}

	run()
	ticker := time.NewTicker(sessionCleanupInterval)
	defer ticker.Stop()
	for range ticker.C {
		run()
	}
}
