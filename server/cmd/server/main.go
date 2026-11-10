package main

import (
	"context"
	"local/quietchat/internal/chat"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		addr := os.Getenv("CHAT_ADDR")
		if addr == "" || strings.HasPrefix(addr, "0.0.0.0:") {
			addr = "127.0.0.1:8088"
		}
		resp, e := (&http.Client{Timeout: 2 * time.Second}).Get("http://" + addr + "/healthz")
		if e != nil {
			os.Exit(1)
		}
		resp.Body.Close()
		if resp.StatusCode != 200 {
			os.Exit(1)
		}
		return
	}
	c := chat.DefaultConfig()
	env := func(k string, d string) string {
		if v := os.Getenv(k); v != "" {
			return v
		}
		return d
	}
	c.Addr = env("CHAT_ADDR", c.Addr)
	c.DataDir = env("CHAT_DATA", c.DataDir)
	c.StorageDriver = env("CHAT_STORAGE", "local")
	if raw := os.Getenv("READ_RECEIPTS_ENABLED"); raw != "" {
		var err error
		c.ReadReceiptsEnabled, err = strconv.ParseBool(raw)
		if err != nil {
			log.Fatal("invalid READ_RECEIPTS_ENABLED")
		}
	}
	c.AllowedOrigin = os.Getenv("CHAT_ORIGIN")
	c.AdminHandle = os.Getenv("CHAT_ADMIN_HANDLE")
	c.AdminPassword = os.Getenv("CHAT_ADMIN_PASSWORD")
	c.XiaomiSecret = env("MIPUSH_APP_SECRET", os.Getenv("XIAOMI_APP_SECRET"))
	c.XiaomiPackage = env("MIPUSH_PACKAGE", os.Getenv("XIAOMI_PACKAGE"))
	c.FCMServiceAccount = os.Getenv("FCM_SERVICE_ACCOUNT_FILE")
	c.XiaomiURL = env("XIAOMI_ENDPOINT", c.XiaomiURL)
	parse := func(key string, def int64) int64 {
		v := os.Getenv(key)
		if v == "" {
			return def
		}
		n, e := strconv.ParseInt(v, 10, 64)
		if e != nil || n <= 0 {
			log.Fatalf("%s must be positive integer", key)
		}
		return n
	}
	c.MediaQuota = parse("CHAT_MEDIA_QUOTA", c.MediaQuota)
	c.MaxFile = parse("CHAT_MAX_FILE", c.MaxFile)
	if os.Getenv("GOMEMLIMIT") == "" {
		debug.SetMemoryLimit(64 << 20)
	}
	if v := os.Getenv("CHAT_ADMIN_PASSWORD_FILE"); v != "" {
		b, e := os.ReadFile(v)
		if e != nil {
			log.Fatal("cannot read bootstrap password file")
		}
		c.AdminPassword = string(b)
		for len(c.AdminPassword) > 0 && (c.AdminPassword[len(c.AdminPassword)-1] == '\n' || c.AdminPassword[len(c.AdminPassword)-1] == '\r') {
			c.AdminPassword = c.AdminPassword[:len(c.AdminPassword)-1]
		}
	}
	a, e := chat.Open(c)
	if e != nil {
		log.Fatal(e)
	}
	srv := &http.Server{Addr: c.Addr, Handler: a.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 90 * time.Second, WriteTimeout: 90 * time.Second, IdleTimeout: 90 * time.Second, MaxHeaderBytes: 16 << 10}
	go func() {
		log.Printf("quietchat listening on %s (no E2EE; TLS via reverse proxy)", c.Addr)
		if e := srv.ListenAndServe(); e != nil && e != http.ErrServerClosed {
			log.Fatal(e)
		}
	}()
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
	a.Close()
}
