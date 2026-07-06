package httpapi

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPrivacySafeLoggerRedactsSensitiveRequestContext(t *testing.T) {
	var buf bytes.Buffer
	logger := NewPrivacySafeLogger(slog.NewJSONHandler(&buf, nil))
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/session", strings.NewReader(`{"token":"magic-secret","email":"alice@example.com","sdp":"v=0","iceCandidate":"candidate:1 typ relay","audio":"base64-audio"}`))
	req.Header.Set("Authorization", "Bearer session-secret")
	req.Header.Set("X-Request-ID", "request-1")

	logger.RequestCompleted(req, PrivacySafeLogFields{
		StatusCode:     http.StatusCreated,
		UserID:         "user-1",
		TeamID:         "team-1",
		ConversationID: "conversation-1",
		EventType:      "auth.session",
		FailureReason:  "token magic-secret belongs to alice@example.com",
	})

	output := buf.String()
	for _, forbidden := range []string{
		"session-secret",
		"magic-secret",
		"alice@example.com",
		"candidate:1",
		"typ relay",
		"base64-audio",
		"v=0",
	} {
		if strings.Contains(output, forbidden) {
			t.Fatalf("log output contains sensitive value %q: %s", forbidden, output)
		}
	}
	for _, required := range []string{
		"request-1",
		"user-1",
		"team-1",
		"conversation-1",
		"auth.session",
		"201",
	} {
		if !strings.Contains(output, required) {
			t.Fatalf("log output missing %q: %s", required, output)
		}
	}
}
