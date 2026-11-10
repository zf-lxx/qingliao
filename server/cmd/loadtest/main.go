// Synthetic loopback load; intentionally reuses ONE receiving session across
// many WS connections. This measures socket/fanout overhead, not 200 real users.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"github.com/gorilla/websocket"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	base := flag.String("url", "http://127.0.0.1:8088", "server")
	n := flag.Int("clients", 200, "connections")
	messages := flag.Int("messages", 100, "messages")
	hold := flag.Duration("hold", 20*time.Second, "hold after sends")
	flag.Parse()
	password := os.Getenv("LOAD_ADMIN_PASSWORD")
	if file := os.Getenv("LOAD_ADMIN_PASSWORD_FILE"); file != "" {
		b, e := os.ReadFile(file)
		if e != nil {
			log.Fatal(e)
		}
		password = strings.TrimSpace(string(b))
	}
	if password == "" {
		log.Fatal("LOAD_ADMIN_PASSWORD[_FILE] required")
	}
	client := &http.Client{Timeout: 15 * time.Second}
	request := func(path, token string, body any) map[string]any {
		b, _ := json.Marshal(body)
		r, _ := http.NewRequest("POST", *base+path, bytes.NewReader(b))
		r.Header.Set("Authorization", "Bearer "+token)
		res, e := client.Do(r)
		if e != nil {
			log.Fatal(e)
		}
		defer res.Body.Close()
		data, _ := io.ReadAll(res.Body)
		if res.StatusCode >= 300 {
			log.Fatalf("%s: %d %s", path, res.StatusCode, data)
		}
		m := map[string]any{}
		if e = json.Unmarshal(data, &m); e != nil {
			log.Fatal(e)
		}
		return m
	}
	admin := request("/v1/auth/login", "", map[string]any{"handle": "admin", "password": password, "platform": "load"})
	at := admin["access_token"].(string)
	inv := request("/v1/invites", at, map[string]any{"uses": 1, "expires_hours": 1})
	bob := request("/v1/auth/register", "", map[string]any{"handle": fmt.Sprintf("load_%d", time.Now().Unix()), "password": password, "invite_code": inv["invite_code"], "platform": "load"})
	bt := bob["access_token"].(string)
	chat := request("/v1/conversations", at, map[string]any{"kind": "direct", "member_ids": []any{bob["user_id"]}})
	cid := chat["id"].(string)
	var received, failures atomic.Int64
	var wg sync.WaitGroup
	conns := []*websocket.Conn{}
	url := "ws" + strings.TrimPrefix(*base, "http") + "/v1/ws"
	start := time.Now()
	for i := 0; i < *n; i++ {
		time.Sleep(12 * time.Millisecond) // Respect per-user 120 frames/sec limit during resume burst.
		h := http.Header{"Authorization": []string{"Bearer " + bt}}
		c, _, e := websocket.DefaultDialer.Dial(url, h)
		if e != nil {
			log.Fatal("dial: ", e)
		}
		var hello map[string]any
		if e = c.ReadJSON(&hello); e != nil {
			log.Fatal(e)
		}
		if e = c.WriteJSON(map[string]any{"v": 1, "op": "sync.resume", "after_event_seq": 0}); e != nil {
			log.Fatal(e)
		}
		conns = append(conns, c)
		wg.Add(1)
		go func(c *websocket.Conn) {
			defer wg.Done()
			for {
				var ev struct {
					Op   string `json:"op"`
					Type string `json:"type"`
				}
				if e := c.ReadJSON(&ev); e != nil {
					return
				}
				if ev.Op == "event" && ev.Type == "message.created" {
					received.Add(1)
				}
				if ev.Op == "error" {
					failures.Add(1)
				}
			}
		}(c)
	}
	fmt.Printf("READY clients=%d setup_ms=%d scenario=one_receiving_session_many_connections\n", len(conns), time.Since(start).Milliseconds())
	sendStart := time.Now()
	for i := 0; i < *messages; i++ {
		request("/v1/conversations/"+cid+"/messages", at, map[string]any{"client_msg_id": fmt.Sprintf("load_%d", i), "kind": "text", "text": "synthetic load message"})
		time.Sleep(10 * time.Millisecond)
	}
	fmt.Printf("SENT messages=%d duration_ms=%d holding=%s\n", *messages, time.Since(sendStart).Milliseconds(), *hold)
	time.Sleep(*hold)
	expected := int64(*n * *messages)
	fmt.Printf("RESULT events_received=%d expected=%d errors=%d elapsed_ms=%d\n", received.Load(), expected, failures.Load(), time.Since(start).Milliseconds())
	for _, c := range conns {
		c.Close()
	}
	wg.Wait()
	if received.Load() != expected || failures.Load() != 0 {
		os.Exit(1)
	}
}
