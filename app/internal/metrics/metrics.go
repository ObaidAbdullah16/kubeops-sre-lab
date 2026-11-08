// Package metrics is a tiny Prometheus text-format registry: counters, gauges
// and one latency histogram. No dependencies, so the image stays small.
package metrics

import (
	"fmt"
	"io"
	"sort"
	"strings"
	"sync"
	"time"
)

// Buckets are chosen around the 300 ms latency SLO.
var Buckets = []float64{0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2.5, 5}

// Registry holds all series.
type Registry struct {
	mu       sync.Mutex
	counters map[string]float64
	gauges   map[string]float64
	hist     map[string]*histogram
	help     map[string]string
}

type histogram struct {
	labels string
	counts []uint64
	sum    float64
	count  uint64
}

// New creates a registry.
func New() *Registry {
	return &Registry{counters: map[string]float64{}, gauges: map[string]float64{}, hist: map[string]*histogram{}, help: map[string]string{}}
}

// Labels renders label pairs: Labels("a", "1", "b", "2") -> {a="1",b="2"}.
func Labels(kv ...string) string {
	if len(kv) < 2 {
		return ""
	}
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`)
	parts := make([]string, 0, len(kv)/2)
	for i := 0; i+1 < len(kv); i += 2 {
		parts = append(parts, fmt.Sprintf(`%s="%s"`, kv[i], r.Replace(kv[i+1])))
	}
	return "{" + strings.Join(parts, ",") + "}"
}

// Help sets the HELP text of a metric family.
func (r *Registry) Help(name, text string) {
	r.mu.Lock()
	r.help[name] = text
	r.mu.Unlock()
}

// Add adds v to a counter.
func (r *Registry) Add(name string, v float64, kv ...string) {
	r.mu.Lock()
	r.counters[name+Labels(kv...)] += v
	r.mu.Unlock()
}

// Set sets a gauge.
func (r *Registry) Set(name string, v float64, kv ...string) {
	r.mu.Lock()
	r.gauges[name+Labels(kv...)] = v
	r.mu.Unlock()
}

// Observe records a duration in the http_request_duration_seconds histogram.
func (r *Registry) Observe(d time.Duration, kv ...string) {
	key := Labels(kv...)
	r.mu.Lock()
	defer r.mu.Unlock()
	h, ok := r.hist[key]
	if !ok {
		h = &histogram{labels: key, counts: make([]uint64, len(Buckets))}
		r.hist[key] = h
	}
	s := d.Seconds()
	for i, b := range Buckets {
		if s <= b {
			h.counts[i]++
		}
	}
	h.sum += s
	h.count++
}

func withLabel(labels, k, v string) string {
	extra := fmt.Sprintf(`%s="%s"`, k, v)
	if labels == "" {
		return "{" + extra + "}"
	}
	return labels[:len(labels)-1] + "," + extra + "}"
}

func (r *Registry) writeFamily(w io.Writer, series map[string]float64, typ string) {
	keys := make([]string, 0, len(series))
	for k := range series {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	seen := map[string]bool{}
	for _, k := range keys {
		base := strings.SplitN(k, "{", 2)[0]
		if !seen[base] {
			if h, ok := r.help[base]; ok {
				fmt.Fprintf(w, "# HELP %s %s\n", base, h)
			}
			fmt.Fprintf(w, "# TYPE %s %s\n", base, typ)
			seen[base] = true
		}
		fmt.Fprintf(w, "%s %g\n", k, series[k])
	}
}

// Write renders everything in the Prometheus exposition format.
func (r *Registry) Write(w io.Writer) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.writeFamily(w, r.counters, "counter")
	r.writeFamily(w, r.gauges, "gauge")
	if len(r.hist) == 0 {
		return
	}
	const name = "http_request_duration_seconds"
	fmt.Fprintf(w, "# HELP %s HTTP request latency.\n# TYPE %s histogram\n", name, name)
	keys := make([]string, 0, len(r.hist))
	for k := range r.hist {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		h := r.hist[k]
		for i, b := range Buckets {
			fmt.Fprintf(w, "%s_bucket%s %d\n", name, withLabel(h.labels, "le", fmt.Sprint(b)), h.counts[i])
		}
		fmt.Fprintf(w, "%s_bucket%s %d\n", name, withLabel(h.labels, "le", "+Inf"), h.count)
		fmt.Fprintf(w, "%s_sum%s %g\n", name, h.labels, h.sum)
		fmt.Fprintf(w, "%s_count%s %d\n", name, h.labels, h.count)
	}
}
