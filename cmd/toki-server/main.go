package main

import (
	"context"
	"database/sql"
	"log"
	"net/http"
	"os"
	"strings"

	_ "github.com/lib/pq"

	"toki/internal/httpapi"
	"toki/internal/store"
)

func main() {
	ctx := context.Background()
	st, closeStore, err := openStore(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer closeStore()

	invites := splitCSV(os.Getenv("TOKI_DEV_INVITES"))
	if len(invites) > 0 {
		if _, err := st.SeedDevelopmentTeam(ctx, "Toki Beta", invites); err != nil {
			log.Fatal(err)
		}
	}

	addr := os.Getenv("TOKI_HTTP_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8080"
	}
	log.Fatal(http.ListenAndServe(addr, httpapi.NewServer(st)))
}

func openStore(ctx context.Context) (store.Store, func(), error) {
	databaseURL := strings.TrimSpace(os.Getenv("TOKI_DATABASE_URL"))
	if databaseURL == "" {
		return store.NewMemoryStore(), func() {}, nil
	}

	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, nil, err
	}
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, nil, err
	}
	if err := applyMetadataMigration(ctx, db); err != nil {
		_ = db.Close()
		return nil, nil, err
	}
	return store.NewPostgresStore(db), func() { _ = db.Close() }, nil
}

func applyMetadataMigration(ctx context.Context, db *sql.DB) error {
	for _, path := range []string{"migrations/001_metadata.sql", "../../migrations/001_metadata.sql"} {
		migration, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		_, err = db.ExecContext(ctx, string(migration))
		return err
	}
	return os.ErrNotExist
}

func splitCSV(value string) []string {
	var out []string
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item != "" {
			out = append(out, item)
		}
	}
	return out
}
