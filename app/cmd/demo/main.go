// Command demo is the SRE lab's demo service.
//
//	demo serve     run the orders API (default)
//	demo loadgen   send steady traffic to the API
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/chaos"
	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/loadgen"
	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/metrics"
	"github.com/ObaidAbdullah16/kubeops-sre-lab/app/internal/server"
)

var version = "dev" // set with -ldflags "-X main.version=..."

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("app", "orders-demo", "version", version)
	cmd := "serve"
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	var err error
	switch cmd {
	case "serve":
		err = serve(ctx, log)
	case "loadgen":
		err = runLoadgen(ctx, log, os.Args[2:])
	case "version":
		_, err = os.Stdout.WriteString(version + "\n")
	default:
		err = errors.New("usage: demo [serve|loadgen|version]")
	}
	if err != nil {
		log.Error("exit", "err", err)
		os.Exit(1)
	}
}

func serve(ctx context.Context, log *slog.Logger) error {
	src := chaos.New(env("CHAOS_DIR", "/etc/chaos"))
	stopWatch := make(chan struct{})
	defer close(stopWatch)
	go src.Watch(5*time.Second, stopWatch)

	s := server.New(log, metrics.New(), src, version, env("POD_NAME", "local"))
	srv := &http.Server{Addr: ":" + env("PORT", "8080"), Handler: s.Handler(), ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second}
	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", srv.Addr)
		errCh <- srv.ListenAndServe()
	}()
	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}
	// Graceful shutdown: fail readiness first so the endpoint is removed, then drain.
	s.Drain()
	delay, _ := strconv.Atoi(env("SHUTDOWN_DELAY_SECONDS", "5"))
	log.Info("draining", "delay_s", delay)
	time.Sleep(time.Duration(delay) * time.Second)
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	return srv.Shutdown(sctx)
}

func runLoadgen(ctx context.Context, log *slog.Logger, args []string) error {
	fs := flag.NewFlagSet("loadgen", flag.ContinueOnError)
	target := fs.String("target", env("TARGET", "http://localhost:8080"), "base URL")
	rps := fs.Float64("rps", 10, "requests per second")
	dur := fs.Duration("duration", 0, "how long (0 = forever)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if v, err := strconv.ParseFloat(os.Getenv("RPS"), 64); err == nil && v > 0 {
		*rps = v
	}
	loadgen.Run(ctx, loadgen.Config{Target: *target, RPS: *rps, Duration: *dur}, log)
	return nil
}
