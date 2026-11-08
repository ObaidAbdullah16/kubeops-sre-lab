// Package chaos reads fault-injection settings that can be changed at runtime.
//
// Settings come from files in a directory (a Kubernetes ConfigMap mounted as a
// volume, e.g. /etc/chaos/error_rate) and are re-read every few seconds, so a
// `kubectl apply` of the ConfigMap changes the behaviour of every pod within
// about a minute - without a restart, exactly like a real bad config push.
package chaos

import (
	"math/rand/v2"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Settings is one snapshot of the chaos knobs.
type Settings struct {
	ErrorRate   float64 // 0..1 share of API requests that fail with 500
	LatencyMS   int     // extra delay added to slow requests
	LatencyRate float64 // 0..1 share of API requests that get the extra delay
	FailReady   bool    // make /readyz fail (pod is removed from the Service)
}

// Source keeps the latest settings.
type Source struct {
	dir string
	mu  sync.RWMutex
	cur Settings
}

// New reads dir once and returns a Source. A missing directory means "no chaos".
func New(dir string) *Source {
	s := &Source{dir: dir}
	s.Reload()
	return s
}

// Static returns a Source with fixed settings (tests).
func Static(st Settings) *Source { return &Source{cur: st} }

// Get returns the current settings.
func (s *Source) Get() Settings {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.cur
}

// Set replaces the settings (tests).
func (s *Source) Set(st Settings) {
	s.mu.Lock()
	s.cur = st
	s.mu.Unlock()
}

func readFloat(dir, name string) float64 {
	b, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return 0
	}
	v, err := strconv.ParseFloat(strings.TrimSpace(string(b)), 64)
	if err != nil || v < 0 {
		return 0
	}
	return v
}

func clamp01(v float64) float64 {
	if v > 1 {
		return 1
	}
	return v
}

// Reload re-reads the directory.
func (s *Source) Reload() {
	if s.dir == "" {
		return
	}
	st := Settings{
		ErrorRate:   clamp01(readFloat(s.dir, "error_rate")),
		LatencyMS:   int(readFloat(s.dir, "latency_ms")),
		LatencyRate: clamp01(readFloat(s.dir, "latency_rate")),
		FailReady:   readFloat(s.dir, "fail_ready") >= 1,
	}
	if st.LatencyMS > 0 && st.LatencyRate == 0 {
		st.LatencyRate = 1
	}
	if st.LatencyMS > 10000 {
		st.LatencyMS = 10000
	}
	s.Set(st)
}

// Watch reloads every interval until stop is closed.
func (s *Source) Watch(interval time.Duration, stop <-chan struct{}) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-stop:
			return
		case <-t.C:
			s.Reload()
		}
	}
}

// ShouldFail decides whether this request fails.
func (st Settings) ShouldFail() bool { return st.ErrorRate > 0 && rand.Float64() < st.ErrorRate }

// Delay returns the injected latency for this request.
func (st Settings) Delay() time.Duration {
	if st.LatencyMS > 0 && rand.Float64() < st.LatencyRate {
		return time.Duration(st.LatencyMS) * time.Millisecond
	}
	return 0
}
