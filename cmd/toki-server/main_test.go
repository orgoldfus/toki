package main

import (
	"context"
	"testing"

	"toki/internal/store"
)

func TestOpenStoreUsesMemoryStoreWithoutDatabaseURL(t *testing.T) {
	t.Setenv("TOKI_DATABASE_URL", "")

	st, closeStore, err := openStore(context.Background())
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	defer closeStore()

	if _, ok := st.(*store.MemoryStore); !ok {
		t.Fatalf("store type = %T, want *store.MemoryStore", st)
	}
}
