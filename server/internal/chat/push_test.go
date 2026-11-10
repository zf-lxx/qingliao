package chat

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

func TestFCMOAuthV1AndInvalidToken(t *testing.T) {
	key, e := rsa.GenerateKey(rand.Reader, 2048)
	if e != nil {
		t.Fatal(e)
	}
	var tokenRequests, sends, mode atomic.Int64
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/token" {
			tokenRequests.Add(1)
			r.ParseForm()
			if r.Form.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" {
				t.Error("grant type")
			}
			parts := strings.Split(r.Form.Get("assertion"), ".")
			if len(parts) != 3 {
				t.Error("missing JWT")
				w.WriteHeader(400)
				return
			}
			sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
			digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
			if rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, digest[:], sig) != nil {
				t.Error("bad JWT signature")
			}
			payload, _ := base64.RawURLEncoding.DecodeString(parts[1])
			var claims map[string]any
			json.Unmarshal(payload, &claims)
			if claims["scope"] != "https://www.googleapis.com/auth/firebase.messaging" || claims["aud"] != server.URL+"/token" {
				t.Error("OAuth scope/audience", claims)
			}
			io.WriteString(w, `{"access_token":"mock-access","token_type":"Bearer","expires_in":3600}`)
			return
		}
		sends.Add(1)
		if r.Header.Get("Authorization") != "Bearer mock-access" || r.URL.Path != "/v1/projects/test-project/messages:send" {
			t.Error("FCM route/auth")
		}
		var request struct {
			Message struct {
				Token   string            `json:"token"`
				Data    map[string]string `json:"data"`
				Android struct {
					Collapse string `json:"collapse_key"`
				} `json:"android"`
			} `json:"message"`
		}
		json.NewDecoder(r.Body).Decode(&request)
		if request.Message.Token != "device-token" || request.Message.Data["chat_id"] != "chat" || request.Message.Data["message_id"] != "message" || request.Message.Android.Collapse != hash("chat")[:20] {
			t.Error("FCM body", request)
		}
		switch mode.Load() {
		case 1:
			w.WriteHeader(404)
			io.WriteString(w, `{"error":{"status":"NOT_FOUND","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`)
		case 2:
			w.WriteHeader(400)
			io.WriteString(w, `{"error":{"status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.BadRequest"}]}}`)
		default:
			io.WriteString(w, `{"name":"projects/test-project/messages/mock"}`)
		}
	}))
	defer server.Close()
	keyBytes := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	b, _ := json.Marshal(map[string]any{"type": "service_account", "project_id": "test-project", "client_email": "test@test-project.iam.gserviceaccount.com", "private_key": string(keyBytes), "token_uri": server.URL + "/token"})
	provider, e := newFCM(context.Background(), b, server.Client(), server.URL+"/v1/projects/test-project/messages:send", true)
	if e != nil {
		t.Fatal(e)
	}
	if tokenRequests.Load() != 0 {
		t.Fatal("minted before send")
	}
	for i := 0; i < 2; i++ {
		if e = provider.Send(context.Background(), "device-token", "chat", "message"); e != nil {
			t.Fatal(e)
		}
	}
	if tokenRequests.Load() != 1 {
		t.Fatal("access token not cached")
	}
	mode.Store(1)
	if e = provider.Send(context.Background(), "device-token", "chat", "message"); !errors.Is(e, ErrInvalidPushToken) {
		t.Fatal(e)
	}
	mode.Store(2)
	if e = provider.Send(context.Background(), "device-token", "chat", "message"); e == nil || errors.Is(e, ErrInvalidPushToken) {
		t.Fatal("payload error wrongly deletes token", e)
	}
	if sends.Load() != 4 {
		t.Fatal(sends.Load())
	}
	if _, e = newFCM(context.Background(), b, server.Client(), "", false); e == nil {
		t.Fatal("production accepted non-Google OAuth issuer")
	}
}
func TestMiPushCollapseAndInvalidRegID(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		if r.Header.Get("Authorization") != "key=mock-secret" || r.Form.Get("notify_id") != chatNotifyID("chat") {
			t.Error("MiPush authorization/collapse")
		}
		var p map[string]string
		json.Unmarshal([]byte(r.Form.Get("payload")), &p)
		if p["message_id"] != "message" || p["chat_id"] != "chat" {
			t.Error(p)
		}
		io.WriteString(w, `{"code":66007,"result":"error"}`)
	}))
	defer s.Close()
	p := XiaomiPush{Secret: "mock-secret", Package: "test.app", Endpoint: s.URL, Client: s.Client()}
	if e := p.Send(context.Background(), "bad-regid", "chat", "message"); !errors.Is(e, ErrInvalidPushToken) {
		t.Fatal(e)
	}
}

type recordedPush struct {
	mu      sync.Mutex
	calls   [][3]string
	invalid bool
}

func (p *recordedPush) Send(ctx context.Context, token, cid, mid string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls = append(p.calls, [3]string{token, cid, mid})
	if p.invalid {
		return ErrInvalidPushToken
	}
	return nil
}
func (p *recordedPush) count() int { p.mu.Lock(); defer p.mu.Unlock(); return len(p.calls) }
func TestPrimaryPushRoutingCoalesceAndCleanup(t *testing.T) {
	mi, fc := &recordedPush{invalid: true}, &recordedPush{}
	f := setupConfig(t, func(c *Config) { c.PushProviders = map[string]PushProvider{"mipush": mi, "fcm": fc} })
	cid := direct(t, f)
	req(t, f.s, "PUT", "/v1/devices/current/push", f.bt, map[string]any{"provider": "mipush", "token": "bad-mi"}, 200)
	second := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "test-password-long", "platform": "android"}, 200)
	token := second["access_token"].(string)
	req(t, f.s, "PUT", "/v1/devices/current/push", token, map[string]any{"provider": "fcm", "token": "fcm-regid"}, 200)
	req(t, f.s, "PUT", "/v1/devices/current/push", token, map[string]any{"provider": "both", "token": "bad"}, 400)
	var last Message
	for i, c := range []string{"a", "b", "c"} {
		_ = i
		var e error
		last, e = f.a.SendMessage(f.admin, cid, Send{ClientID: c, Text: "coalesced"})
		if e != nil {
			t.Fatal(e)
		}
	}
	f.a.processPush()
	if mi.count() != 1 || fc.count() != 1 {
		t.Fatal("wrong provider fanout", mi.count(), fc.count())
	}
	fc.mu.Lock()
	msg := fc.calls[0][2]
	fc.mu.Unlock()
	if msg != last.ID {
		t.Fatal("did not coalesce latest", msg, last.ID)
	}
	var provider, pushToken string
	f.a.DB.QueryRow("SELECT push_provider,push_token FROM devices WHERE id=?", f.bob.DeviceID).Scan(&provider, &pushToken)
	if provider != "none" || pushToken != "" {
		t.Fatal("invalid token not cleared")
	}
	var n int
	f.a.DB.QueryRow("SELECT count(*) FROM push_jobs WHERE last_error='coalesced'").Scan(&n)
	if n != 2 {
		t.Fatal(n)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+cid+"/state", f.bt, map[string]any{"mute_until": "forever"}, 200)
	f.a.SendMessage(f.admin, cid, Send{ClientID: "mute", Text: "muted"})
	f.a.processPush()
	if fc.count() != 1 {
		t.Fatal("muted push sent")
	}
	req(t, f.s, "PUT", "/v1/devices/current/push", token, map[string]any{"provider": "none", "token": ""}, 200)
}

func TestOfflineDevicePushWithAnotherDeviceOnline(t *testing.T) {
	mi := &recordedPush{}
	f := setupConfig(t, func(c *Config) { c.PushProviders = map[string]PushProvider{"mipush": mi} })
	cid := direct(t, f)
	req(t, f.s, "PUT", "/v1/devices/current/push", f.bt, map[string]any{"provider": "mipush", "token": "offline-phone"}, 200)
	other := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "test-password-long", "platform": "desktop"}, 200)
	socket := dial(t, f, other["access_token"].(string))
	defer socket.Close()
	if _, e := f.a.SendMessage(f.admin, cid, Send{ClientID: "offline-device", Text: "message"}); e != nil {
		t.Fatal(e)
	}
	f.a.processPush()
	if mi.count() != 1 {
		t.Fatal("another online device suppressed phone notification")
	}
}
