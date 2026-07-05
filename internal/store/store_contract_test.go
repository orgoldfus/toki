package store_test

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"testing"

	_ "github.com/lib/pq"

	"toki/internal/store"
)

func TestMemoryStoreContract(t *testing.T) {
	runStoreContract(t, func(t *testing.T) store.Store {
		t.Helper()
		return store.NewMemoryStore()
	})
}

func TestPostgresStoreContract(t *testing.T) {
	dsn := os.Getenv("TOKI_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TOKI_TEST_DATABASE_URL is not set")
	}

	runStoreContract(t, func(t *testing.T) store.Store {
		t.Helper()

		db, err := sql.Open("postgres", dsn)
		if err != nil {
			t.Fatalf("open postgres: %v", err)
		}
		t.Cleanup(func() {
			_ = db.Close()
		})
		resetPostgresSchema(t, db)

		return store.NewPostgresStore(db)
	})
}

func runStoreContract(t *testing.T, newStore func(*testing.T) store.Store) {
	t.Run("invite only sessions and revocation", func(t *testing.T) {
		ctx := context.Background()
		st := newStore(t)
		if _, err := st.SeedDevelopmentTeam(ctx, "Toki Beta", []string{"alice@example.com"}); err != nil {
			t.Fatalf("seed team: %v", err)
		}

		if _, err := st.CreateMagicLink(ctx, "not-invited@example.com"); !errors.Is(err, store.ErrForbidden) {
			t.Fatalf("non-invited magic link error = %v, want ErrForbidden", err)
		}

		magicToken, err := st.CreateMagicLink(ctx, "ALICE@example.com")
		if err != nil {
			t.Fatalf("create magic link: %v", err)
		}
		bundle, err := st.CreateSession(ctx, magicToken, "Alice Mac")
		if err != nil {
			t.Fatalf("create session: %v", err)
		}
		if bundle.User.Email != "alice@example.com" {
			t.Fatalf("session email = %q, want alice@example.com", bundle.User.Email)
		}
		if len(bundle.Memberships) != 1 || len(bundle.Teams) != 1 || len(bundle.Devices) != 1 {
			t.Fatalf("bundle counts = memberships:%d teams:%d devices:%d, want 1 each", len(bundle.Memberships), len(bundle.Teams), len(bundle.Devices))
		}

		lookedUp, err := st.LookupSession(ctx, bundle.Session.Token)
		if err != nil {
			t.Fatalf("lookup session: %v", err)
		}
		if lookedUp.User.ID != bundle.User.ID {
			t.Fatalf("lookup user id = %q, want %q", lookedUp.User.ID, bundle.User.ID)
		}
		if err := st.RevokeSession(ctx, bundle.Session.Token); err != nil {
			t.Fatalf("revoke session: %v", err)
		}
		if _, err := st.LookupSession(ctx, bundle.Session.Token); !errors.Is(err, store.ErrForbidden) {
			t.Fatalf("revoked lookup error = %v, want ErrForbidden", err)
		}
		if err := st.RevokeSession(ctx, bundle.Session.Token); !errors.Is(err, store.ErrAlreadyRevoked) {
			t.Fatalf("second revoke error = %v, want ErrAlreadyRevoked", err)
		}
	})

	t.Run("conversation membership rules", func(t *testing.T) {
		ctx := context.Background()
		st := newStore(t)
		if _, err := st.SeedDevelopmentTeam(ctx, "Toki Beta", []string{
			"alice@example.com",
			"bob@example.com",
			"carol@example.com",
			"member1@example.com", "member2@example.com", "member3@example.com",
			"member4@example.com", "member5@example.com", "member6@example.com",
			"member7@example.com", "member8@example.com", "member9@example.com",
			"member10@example.com",
		}); err != nil {
			t.Fatalf("seed beta team: %v", err)
		}
		if _, err := st.SeedDevelopmentTeam(ctx, "Other Team", []string{"outsider@example.com"}); err != nil {
			t.Fatalf("seed other team: %v", err)
		}

		alice := signInStoreUser(t, st, "alice@example.com")
		bob := signInStoreUser(t, st, "bob@example.com")
		carol := signInStoreUser(t, st, "carol@example.com")
		outsider := signInStoreUser(t, st, "outsider@example.com")

		direct, err := st.CreateConversation(ctx, alice.User.ID, store.CreateConversationParams{
			Type:      store.ConversationDirect,
			MemberIDs: []string{bob.User.ID},
		})
		if err != nil {
			t.Fatalf("create direct: %v", err)
		}
		duplicate, err := st.CreateConversation(ctx, alice.User.ID, store.CreateConversationParams{
			Type:      store.ConversationDirect,
			MemberIDs: []string{bob.User.ID},
		})
		if err != nil {
			t.Fatalf("create duplicate direct: %v", err)
		}
		if duplicate.ID != direct.ID {
			t.Fatalf("duplicate direct id = %q, want %q", duplicate.ID, direct.ID)
		}

		aliceConversations, err := st.ListConversationsForUser(ctx, alice.User.ID)
		if err != nil {
			t.Fatalf("list alice conversations: %v", err)
		}
		bobConversations, err := st.ListConversationsForUser(ctx, bob.User.ID)
		if err != nil {
			t.Fatalf("list bob conversations: %v", err)
		}
		carolConversations, err := st.ListConversationsForUser(ctx, carol.User.ID)
		if err != nil {
			t.Fatalf("list carol conversations: %v", err)
		}
		if len(aliceConversations) != 1 || aliceConversations[0].ID != direct.ID {
			t.Fatalf("alice conversations = %+v, want direct only", aliceConversations)
		}
		if len(bobConversations) != 1 || bobConversations[0].ID != direct.ID {
			t.Fatalf("bob conversations = %+v, want direct only", bobConversations)
		}
		if len(carolConversations) != 0 {
			t.Fatalf("carol conversations len = %d, want 0", len(carolConversations))
		}

		if _, err := st.CreateConversation(ctx, alice.User.ID, store.CreateConversationParams{
			Type:      store.ConversationDirect,
			MemberIDs: []string{outsider.User.ID},
		}); !errors.Is(err, store.ErrInvalidInput) {
			t.Fatalf("non-team direct error = %v, want ErrInvalidInput", err)
		}

		memberIDs := []string{
			signInStoreUser(t, st, "member1@example.com").User.ID,
			signInStoreUser(t, st, "member2@example.com").User.ID,
			signInStoreUser(t, st, "member3@example.com").User.ID,
			signInStoreUser(t, st, "member4@example.com").User.ID,
			signInStoreUser(t, st, "member5@example.com").User.ID,
			signInStoreUser(t, st, "member6@example.com").User.ID,
			signInStoreUser(t, st, "member7@example.com").User.ID,
			signInStoreUser(t, st, "member8@example.com").User.ID,
			signInStoreUser(t, st, "member9@example.com").User.ID,
			signInStoreUser(t, st, "member10@example.com").User.ID,
		}
		if _, err := st.CreateConversation(ctx, alice.User.ID, store.CreateConversationParams{
			Type:      store.ConversationGroup,
			MemberIDs: memberIDs,
		}); !errors.Is(err, store.ErrInvalidInput) {
			t.Fatalf("oversized group error = %v, want ErrInvalidInput", err)
		}

		group, err := st.CreateConversation(ctx, alice.User.ID, store.CreateConversationParams{
			Type:        store.ConversationGroup,
			DisplayName: "Beta Team",
			MemberIDs:   memberIDs[:9],
		})
		if err != nil {
			t.Fatalf("create max group: %v", err)
		}
		if len(group.Members) != store.MaxGroupMembers {
			t.Fatalf("group member count = %d, want %d", len(group.Members), store.MaxGroupMembers)
		}
		if _, err := st.AddConversationMembers(ctx, alice.User.ID, group.ID, []string{memberIDs[9]}); !errors.Is(err, store.ErrInvalidInput) {
			t.Fatalf("adding eleventh group member error = %v, want ErrInvalidInput", err)
		}
	})
}

func signInStoreUser(t *testing.T, st store.Store, email string) store.SessionBundle {
	t.Helper()

	ctx := context.Background()
	magicToken, err := st.CreateMagicLink(ctx, email)
	if err != nil {
		t.Fatalf("create magic link for %s: %v", email, err)
	}
	bundle, err := st.CreateSession(ctx, magicToken, email+" Mac")
	if err != nil {
		t.Fatalf("create session for %s: %v", email, err)
	}
	return bundle
}

func resetPostgresSchema(t *testing.T, db *sql.DB) {
	t.Helper()

	if _, err := db.Exec(`
		DROP TABLE IF EXISTS conversation_members;
		DROP TABLE IF EXISTS conversations;
		DROP TABLE IF EXISTS sessions;
		DROP TABLE IF EXISTS devices;
		DROP TABLE IF EXISTS memberships;
		DROP TABLE IF EXISTS invitations;
		DROP TABLE IF EXISTS users;
		DROP TABLE IF EXISTS teams;
	`); err != nil {
		t.Fatalf("drop postgres schema: %v", err)
	}

	migrationPath := filepath.Join("..", "..", "migrations", "001_metadata.sql")
	migration, err := os.ReadFile(migrationPath)
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}
	if _, err := db.Exec(string(migration)); err != nil {
		t.Fatalf("apply migration: %v", err)
	}
}
