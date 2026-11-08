package chaos

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestReloadFromDirectory(t *testing.T) {
	dir := t.TempDir()
	s := New(dir)
	if s.Get() != (Settings{}) {
		t.Fatalf("empty dir should mean no chaos: %+v", s.Get())
	}
	write := func(name, v string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(v), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("error_rate", "0.2\n")
	write("latency_ms", "400")
	write("fail_ready", "1")
	s.Reload()
	got := s.Get()
	if got.ErrorRate != 0.2 || got.LatencyMS != 400 || got.LatencyRate != 1 || !got.FailReady {
		t.Fatalf("unexpected settings %+v", got)
	}
	write("error_rate", "7") // clamped
	write("latency_ms", "junk")
	s.Reload()
	if got := s.Get(); got.ErrorRate != 1 || got.LatencyMS != 0 {
		t.Fatalf("clamping/parsing failed: %+v", got)
	}
}

func TestDecisions(t *testing.T) {
	if (Settings{}).ShouldFail() || (Settings{}).Delay() != 0 {
		t.Fatal("zero settings must not inject anything")
	}
	if !(Settings{ErrorRate: 1}).ShouldFail() {
		t.Fatal("error_rate=1 must always fail")
	}
	if d := (Settings{LatencyMS: 50, LatencyRate: 1}).Delay(); d != 50*time.Millisecond {
		t.Fatalf("delay = %v", d)
	}
}
