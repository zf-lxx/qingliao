package chat

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"io"
	"net/http"
	"os"
	"regexp"
)

var ErrInvalidPushToken = errors.New("invalid push token")
var ErrPushNotConfigured = errors.New("push provider not configured")

type FCMPush struct {
	ProjectID, Endpoint string
	Tokens              oauth2.TokenSource
	Client              *http.Client
}

var projectRE = regexp.MustCompile(`^[a-z][a-z0-9-]{4,62}$`)

func newFCM(ctx context.Context, b []byte, client *http.Client, endpoint string, testing bool) (*FCMPush, error) {
	var meta struct {
		Type     string `json:"type"`
		Project  string `json:"project_id"`
		TokenURL string `json:"token_uri"`
	}
	if json.Unmarshal(b, &meta) != nil || meta.Type != "service_account" || !projectRE.MatchString(meta.Project) {
		return nil, ErrInvalid
	}
	if !testing && meta.TokenURL != "https://oauth2.googleapis.com/token" && meta.TokenURL != "https://accounts.google.com/o/oauth2/token" {
		return nil, ErrInvalid
	}
	cfg, e := google.JWTConfigFromJSON(b, "https://www.googleapis.com/auth/firebase.messaging")
	if e != nil {
		return nil, ErrInvalid
	}
	block, _ := pem.Decode(cfg.PrivateKey)
	if block == nil {
		return nil, ErrInvalid
	}
	var key any
	if k, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		key = k
	} else if k, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		key = k
	} else {
		return nil, ErrInvalid
	}
	rsaKey, ok := key.(*rsa.PrivateKey)
	if !ok || rsaKey.N.BitLen() < 2048 || rsaKey.Validate() != nil || cfg.Email == "" {
		return nil, ErrInvalid
	}
	ctx = context.WithValue(ctx, oauth2.HTTPClient, client)
	if endpoint == "" {
		endpoint = "https://fcm.googleapis.com/v1/projects/" + meta.Project + "/messages:send"
	}
	return &FCMPush{ProjectID: meta.Project, Endpoint: endpoint, Tokens: cfg.TokenSource(ctx), Client: client}, nil
}
func loadFCM(ctx context.Context, path string, client *http.Client) (*FCMPush, error) {
	f, e := os.Open(path)
	if e != nil {
		return nil, fmt.Errorf("cannot open FCM service account file")
	}
	defer f.Close()
	b, e := io.ReadAll(io.LimitReader(f, 1<<20))
	if e != nil {
		return nil, ErrInvalid
	}
	return newFCM(ctx, b, client, "", false)
}
func (f *FCMPush) Send(ctx context.Context, token, cid, mid string) error {
	if f == nil || f.Tokens == nil {
		return ErrPushNotConfigured
	}
	auth, e := f.Tokens.Token()
	if e != nil {
		return fmt.Errorf("fcm_oauth_error")
	}
	data := map[string]any{"message": map[string]any{"token": token, "notification": map[string]string{"title": "轻聊", "body": "你有一条新消息"}, "data": map[string]string{"message_id": mid, "chat_id": cid, "conversation_id": cid}, "android": map[string]any{"priority": "HIGH", "collapse_key": hash(cid)[:20], "ttl": "86400s", "notification": map[string]string{"tag": hash(cid)[:20]}}}}
	b, _ := json.Marshal(data)
	req, e := http.NewRequestWithContext(ctx, "POST", f.Endpoint, bytes.NewReader(b))
	if e != nil {
		return e
	}
	req.Header.Set("Authorization", "Bearer "+auth.AccessToken)
	req.Header.Set("Content-Type", "application/json")
	res, e := f.Client.Do(req)
	if e != nil {
		return fmt.Errorf("fcm_transport_error")
	}
	defer res.Body.Close()
	body, e := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	if e != nil {
		return fmt.Errorf("fcm_bad_response")
	}
	if res.StatusCode >= 200 && res.StatusCode < 300 {
		return nil
	}
	var result struct {
		Error struct {
			Status  string `json:"status"`
			Details []struct {
				Type string `json:"@type"`
				Code string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	json.Unmarshal(body, &result)
	if result.Error.Status == "UNREGISTERED" {
		return ErrInvalidPushToken
	}
	for _, d := range result.Error.Details {
		if d.Type == "type.googleapis.com/google.firebase.fcm.v1.FcmError" && (d.Code == "UNREGISTERED" || d.Code == "INVALID_ARGUMENT") {
			return ErrInvalidPushToken
		}
	}
	return fmt.Errorf("fcm_http_%d", res.StatusCode)
}
