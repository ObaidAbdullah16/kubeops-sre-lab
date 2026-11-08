package loadgen

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestRunSendsTraffic(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			w.WriteHeader(201)
			return
		}
		w.WriteHeader(200)
	}))
	defer srv.Close()
	st := Run(context.Background(), Config{Target: srv.URL, RPS: 100, Duration: 500 * time.Millisecond}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if st.Sent.Load() < 20 || st.ServerErr.Load() != 0 {
		t.Fatalf("sent=%d server_errors=%d", st.Sent.Load(), st.ServerErr.Load())
	}
}
