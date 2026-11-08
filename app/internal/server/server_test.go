package server

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/chaos"
	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/metrics"
)

func newServer(st chaos.Settings) (*Server, http.Handler) {
	s := New(slog.New(slog.NewTextHandler(io.Discard, nil)), metrics.New(), chaos.Static(st), "test", "pod-1")
	return s, s.Handler()
}

func call(h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, r))
	return rec
}

func TestOrdersCRUD(t *testing.T) {
	_, h := newServer(chaos.Settings{})
	if rec := call(h, "POST", "/api/orders", `{"item":"book","quantity":2}`); rec.Code != 201 {
		t.Fatalf("create = %d %s", rec.Code, rec.Body)
	}
	if rec := call(h, "GET", "/api/orders/1", ""); rec.Code != 200 || !strings.Contains(rec.Body.String(), "book") {
		t.Fatalf("get = %d %s", rec.Code, rec.Body)
	}
	if rec := call(h, "GET", "/api/orders", ""); rec.Code != 200 || !strings.Contains(rec.Body.String(), `"id":1`) {
		t.Fatalf("list = %d %s", rec.Code, rec.Body)
	}
	if rec := call(h, "GET", "/api/orders/99", ""); rec.Code != 404 {
		t.Fatalf("missing = %d", rec.Code)
	}
	for _, bad := range []string{`{}`, `{"item":"x","quantity":0}`, `nope`} {
		if rec := call(h, "POST", "/api/orders", bad); rec.Code != 400 {
			t.Fatalf("%s -> %d", bad, rec.Code)
		}
	}
}

func TestChaosErrorRate(t *testing.T) {
	_, h := newServer(chaos.Settings{ErrorRate: 1})
	if rec := call(h, "GET", "/api/orders", ""); rec.Code != 500 {
		t.Fatalf("with error_rate=1 got %d", rec.Code)
	}
	// Health endpoints are never affected, so Kubernetes does not restart pods
	// that are "only" returning errors - the SLO alerts must catch it.
	if rec := call(h, "GET", "/healthz", ""); rec.Code != 200 {
		t.Fatalf("healthz = %d", rec.Code)
	}
}

func TestReadinessAndDrain(t *testing.T) {
	s, h := newServer(chaos.Settings{})
	if rec := call(h, "GET", "/readyz", ""); rec.Code != 200 {
		t.Fatalf("readyz = %d", rec.Code)
	}
	s.Drain()
	if rec := call(h, "GET", "/readyz", ""); rec.Code != 503 {
		t.Fatalf("readyz while draining = %d", rec.Code)
	}
	_, h2 := newServer(chaos.Settings{FailReady: true})
	if rec := call(h2, "GET", "/readyz", ""); rec.Code != 503 {
		t.Fatalf("readyz with fail_ready = %d", rec.Code)
	}
}

func TestMetrics(t *testing.T) {
	_, h := newServer(chaos.Settings{ErrorRate: 0.25})
	for i := 0; i < 40; i++ {
		call(h, "GET", "/api/orders", "")
	}
	body := call(h, "GET", "/metrics", "").Body.String()
	for _, want := range []string{
		`http_requests_total{route="/api/orders",method="GET",code="200"}`,
		`http_requests_total{route="/api/orders",method="GET",code="500"}`,
		`http_request_duration_seconds_bucket{route="/api/orders",method="GET",le="0.3"}`,
		`demo_chaos_error_rate 0.25`,
		`demo_build_info{version="test"} 1`,
		"# TYPE http_requests_total counter",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("metrics missing %q\n%s", want, body)
		}
	}
}
