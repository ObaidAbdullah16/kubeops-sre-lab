// Package loadgen sends a steady mix of requests to the demo service so the
// SLO dashboards always have traffic (and burn alerts can fire during chaos).
package loadgen

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"sync/atomic"
	"time"
)

// Config controls the generator.
type Config struct {
	Target   string        // base URL, e.g. http://demo-app.demo.svc
	RPS      float64       // requests per second
	Duration time.Duration // 0 = until ctx is cancelled
	Report   time.Duration // how often to log a summary
}

// Stats are counted with atomics so the report never blocks the senders.
type Stats struct {
	Sent, OK, ClientErr, ServerErr, Failed atomic.Int64
}

// Run sends requests until the duration elapses or ctx is cancelled.
func Run(ctx context.Context, cfg Config, log *slog.Logger) *Stats {
	if cfg.RPS <= 0 {
		cfg.RPS = 10
	}
	if cfg.Report <= 0 {
		cfg.Report = 30 * time.Second
	}
	if cfg.Duration > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, cfg.Duration)
		defer cancel()
	}
	client := &http.Client{Timeout: 5 * time.Second}
	st := &Stats{}
	tick := time.NewTicker(time.Duration(float64(time.Second) / cfg.RPS))
	defer tick.Stop()
	report := time.NewTicker(cfg.Report)
	defer report.Stop()
	sem := make(chan struct{}, 64) // at most 64 requests in flight
	for {
		select {
		case <-ctx.Done():
			log.Info("loadgen finished", "sent", st.Sent.Load(), "ok", st.OK.Load(), "server_errors", st.ServerErr.Load(), "failed", st.Failed.Load())
			return st
		case <-report.C:
			log.Info("loadgen", "sent", st.Sent.Load(), "ok", st.OK.Load(), "client_errors", st.ClientErr.Load(), "server_errors", st.ServerErr.Load(), "failed", st.Failed.Load())
		case <-tick.C:
			select {
			case sem <- struct{}{}:
			default:
				st.Failed.Add(1) // service too slow: count as failed, do not pile up
				continue
			}
			go func() {
				defer func() { <-sem }()
				one(ctx, client, cfg.Target, st)
			}()
		}
	}
}

func one(ctx context.Context, c *http.Client, base string, st *Stats) {
	var req *http.Request
	switch p := rand.Float64(); {
	case p < 0.7:
		req, _ = http.NewRequestWithContext(ctx, http.MethodGet, base+"/api/orders", nil)
	case p < 0.9:
		body := fmt.Sprintf(`{"item":"widget-%d","quantity":%d}`, rand.IntN(100), 1+rand.IntN(5))
		req, _ = http.NewRequestWithContext(ctx, http.MethodPost, base+"/api/orders", bytes.NewBufferString(body))
		req.Header.Set("Content-Type", "application/json")
	default:
		req, _ = http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("%s/api/orders/%d", base, 1+rand.IntN(50)), nil)
	}
	st.Sent.Add(1)
	resp, err := c.Do(req)
	if err != nil {
		if ctx.Err() == nil {
			st.Failed.Add(1)
		}
		return
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	switch {
	case resp.StatusCode >= 500:
		st.ServerErr.Add(1)
	case resp.StatusCode >= 400:
		st.ClientErr.Add(1) // 404 for random ids is expected
	default:
		st.OK.Add(1)
	}
}
