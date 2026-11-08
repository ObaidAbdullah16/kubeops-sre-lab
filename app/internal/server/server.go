// Package server is the "orders" demo service used in the SRE lab.
package server

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/chaos"
	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/metrics"
)

// Order is a fake order kept in memory.
type Order struct {
	ID        int       `json:"id"`
	Item      string    `json:"item"`
	Quantity  int       `json:"quantity"`
	CreatedAt time.Time `json:"created_at"`
}

// Server holds the in-memory state and dependencies.
type Server struct {
	Log      *slog.Logger
	Metrics  *metrics.Registry
	Chaos    *chaos.Source
	Version  string
	Pod      string
	draining atomic.Bool

	mu     sync.Mutex
	orders []Order
	nextID int
}

// New creates a server.
func New(log *slog.Logger, m *metrics.Registry, c *chaos.Source, version, pod string) *Server {
	m.Help("http_requests_total", "HTTP requests by route, method and status code.")
	m.Help("demo_orders_created_total", "Orders created.")
	m.Help("demo_chaos_error_rate", "Injected error rate (0-1).")
	m.Help("demo_chaos_latency_seconds", "Injected latency.")
	m.Set("demo_build_info", 1, "version", version)
	return &Server{Log: log, Metrics: m, Chaos: c, Version: version, Pod: pod, nextID: 1}
}

// Drain makes /readyz fail so Kubernetes stops sending traffic before shutdown.
func (s *Server) Drain() { s.draining.Store(true) }

// Handler returns the HTTP handler with middleware.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { writeJSON(w, 200, map[string]string{"status": "ok"}) })
	mux.HandleFunc("GET /readyz", s.readyz)
	mux.HandleFunc("GET /metrics", s.metrics)
	mux.HandleFunc("GET /api/orders", s.list)
	mux.HandleFunc("POST /api/orders", s.create)
	mux.HandleFunc("GET /api/orders/{id}", s.get)
	mux.HandleFunc("GET /{$}", s.index)
	return s.middleware(mux)
}

type recorder struct {
	http.ResponseWriter
	code int
}

func (r *recorder) WriteHeader(code int) {
	r.code = code
	r.ResponseWriter.WriteHeader(code)
}

func route(p string) string {
	switch {
	case p == "/api/orders":
		return "/api/orders"
	case strings.HasPrefix(p, "/api/orders/"):
		return "/api/orders/{id}"
	case p == "/healthz", p == "/readyz", p == "/metrics", p == "/":
		return p
	}
	return "other"
}

func (s *Server) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &recorder{ResponseWriter: w, code: 200}
		rt := route(r.URL.Path)
		defer func() {
			if v := recover(); v != nil {
				s.Log.Error("panic", "err", fmt.Sprint(v))
				rec.WriteHeader(500)
			}
			d := time.Since(start)
			s.Metrics.Add("http_requests_total", 1, "route", rt, "method", r.Method, "code", strconv.Itoa(rec.code))
			s.Metrics.Observe(d, "route", rt, "method", r.Method)
			if strings.HasPrefix(rt, "/api/") {
				level := slog.LevelInfo
				if rec.code >= 500 {
					level = slog.LevelError
				}
				s.Log.Log(r.Context(), level, "request", "method", r.Method, "path", r.URL.Path, "route", rt,
					"status", rec.code, "duration_ms", float64(d.Microseconds())/1000, "pod", s.Pod)
			}
		}()
		if strings.HasPrefix(rt, "/api/") {
			st := s.Chaos.Get()
			if d := st.Delay(); d > 0 {
				time.Sleep(d)
			}
			if st.ShouldFail() {
				writeJSON(rec, http.StatusInternalServerError, map[string]string{"error": "injected failure (chaos error_rate)"})
				return
			}
		}
		next.ServeHTTP(rec, r)
	})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) readyz(w http.ResponseWriter, _ *http.Request) {
	if s.draining.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "draining"})
		return
	}
	if s.Chaos.Get().FailReady {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not ready (chaos fail_ready)"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (s *Server) metrics(w http.ResponseWriter, _ *http.Request) {
	st := s.Chaos.Get()
	s.Metrics.Set("demo_chaos_error_rate", st.ErrorRate)
	s.Metrics.Set("demo_chaos_latency_seconds", float64(st.LatencyMS)/1000)
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	s.Metrics.Write(w)
}

func (s *Server) index(w http.ResponseWriter, _ *http.Request) {
	st := s.Chaos.Get()
	writeJSON(w, http.StatusOK, map[string]any{
		"service": "orders-demo", "version": s.Version, "pod": s.Pod,
		"chaos":     map[string]any{"error_rate": st.ErrorRate, "latency_ms": st.LatencyMS, "latency_rate": st.LatencyRate, "fail_ready": st.FailReady},
		"endpoints": []string{"GET /api/orders", "POST /api/orders", "GET /api/orders/{id}", "GET /metrics", "GET /healthz", "GET /readyz"},
	})
}

func (s *Server) list(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	n := len(s.orders)
	start := max(0, n-50)
	out := make([]Order, n-start)
	copy(out, s.orders[start:])
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Item     string `json:"item"`
		Quantity int    `json:"quantity"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048)).Decode(&in); err != nil || in.Item == "" || len(in.Item) > 100 || in.Quantity < 1 || in.Quantity > 1000 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": `send {"item": "<1-100 chars>", "quantity": 1-1000}`})
		return
	}
	s.mu.Lock()
	o := Order{ID: s.nextID, Item: in.Item, Quantity: in.Quantity, CreatedAt: time.Now().UTC()}
	s.nextID++
	s.orders = append(s.orders, o)
	if len(s.orders) > 1000 { // bounded memory
		s.orders = s.orders[len(s.orders)-1000:]
	}
	s.mu.Unlock()
	s.Metrics.Add("demo_orders_created_total", 1)
	writeJSON(w, http.StatusCreated, o)
}

func (s *Server) get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id must be a number"})
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, o := range s.orders {
		if o.ID == id {
			writeJSON(w, http.StatusOK, o)
			return
		}
	}
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "order not found"})
}
