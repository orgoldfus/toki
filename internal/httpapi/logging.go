package httpapi

import (
	"bufio"
	"log/slog"
	"net"
	"net/http"
	"strings"
)

type PrivacySafeLogFields struct {
	StatusCode     int
	UserID         string
	TeamID         string
	ConversationID string
	EventType      string
	FailureReason  string
}

type PrivacySafeLogger struct {
	logger *slog.Logger
}

func NewPrivacySafeLogger(handler slog.Handler) *PrivacySafeLogger {
	return &PrivacySafeLogger{logger: slog.New(handler)}
}

func (l *PrivacySafeLogger) RequestCompleted(r *http.Request, fields PrivacySafeLogFields) {
	if l == nil || l.logger == nil {
		return
	}

	attrs := []any{
		"request_id", requestID(r),
		"method", r.Method,
		"path", r.URL.Path,
		"status_code", fields.StatusCode,
		"event_type", redactedText(fields.EventType),
	}
	if fields.UserID != "" {
		attrs = append(attrs, "user_id", fields.UserID)
	}
	if fields.TeamID != "" {
		attrs = append(attrs, "team_id", fields.TeamID)
	}
	if fields.ConversationID != "" {
		attrs = append(attrs, "conversation_id", fields.ConversationID)
	}
	if fields.FailureReason != "" {
		attrs = append(attrs, "failure_reason", redactedText(fields.FailureReason))
	}

	l.logger.InfoContext(r.Context(), "request completed", attrs...)
}

func requestID(r *http.Request) string {
	if value := strings.TrimSpace(r.Header.Get("X-Request-ID")); value != "" {
		return redactedText(value)
	}
	return "missing"
}

func redactedText(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return trimmed
	}
	lower := strings.ToLower(trimmed)
	for _, marker := range []string{
		"@",
		"token",
		"magic-link",
		"candidate:",
		"typ relay",
		"sdp",
		"v=0",
		"audio",
		"replay",
	} {
		if strings.Contains(lower, marker) {
			return "[redacted]"
		}
	}
	return trimmed
}

type statusRecordingResponseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (w *statusRecordingResponseWriter) WriteHeader(statusCode int) {
	w.statusCode = statusCode
	w.ResponseWriter.WriteHeader(statusCode)
}

func (w *statusRecordingResponseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hijacker, ok := w.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, http.ErrNotSupported
	}
	w.statusCode = http.StatusSwitchingProtocols
	return hijacker.Hijack()
}

func (w *statusRecordingResponseWriter) Flush() {
	flusher, ok := w.ResponseWriter.(http.Flusher)
	if ok {
		flusher.Flush()
	}
}
