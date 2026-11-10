package chat

import (
	"context"
	"database/sql"
	"golang.org/x/net/html"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

type LinkPreview struct {
	ID          string `json:"id"`
	URL         string `json:"url"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Image       string `json:"image,omitempty"`
	SiteName    string `json:"site_name,omitempty"`
	FetchedAt   int64  `json:"fetched_at"`
}

var deniedNetworks = func() []*net.IPNet {
	out := []*net.IPNet{}
	for _, cidr := range []string{"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16", "192.88.99.0/24", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4", "::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8", "2001:db8::/32", "2001::/32", "2002::/16"} {
		_, n, _ := net.ParseCIDR(cidr)
		out = append(out, n)
	}
	return out
}()

func publicIP(ip net.IP) bool {
	if ip == nil || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return false
	}
	for _, n := range deniedNetworks {
		if n.Contains(ip) {
			return false
		}
	}
	if ip.To4() == nil {
		_, global, _ := net.ParseCIDR("2000::/3")
		if !global.Contains(ip) {
			return false
		}
	}
	return true
}
func previewURL(raw string) (*url.URL, error) {
	u, e := safeURL(raw)
	if e != nil {
		return nil, e
	}
	if p := u.Port(); p != "" && p != "80" && p != "443" {
		return nil, ErrForbidden
	}
	host := strings.TrimSuffix(strings.ToLower(u.Hostname()), ".")
	if host == "localhost" || strings.HasSuffix(host, ".localhost") || strings.HasSuffix(host, ".local") {
		return nil, ErrForbidden
	}
	if ip := net.ParseIP(host); ip != nil && !publicIP(ip) {
		return nil, ErrForbidden
	}
	u.Fragment = ""
	return u, nil
}
func resolvePublic(ctx context.Context, host string) ([]net.IPAddr, error) {
	addrs, e := net.DefaultResolver.LookupIPAddr(ctx, host)
	if e != nil || len(addrs) == 0 || len(addrs) > 32 {
		return nil, ErrForbidden
	}
	for _, addr := range addrs {
		if !publicIP(addr.IP) {
			return nil, ErrForbidden
		}
	}
	return addrs, nil
}
func previewClient() *http.Client {
	tr := &http.Transport{Proxy: nil, MaxIdleConns: 4, IdleConnTimeout: 10 * time.Second, ResponseHeaderTimeout: 3 * time.Second, TLSHandshakeTimeout: 3 * time.Second, DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
		host, port, e := net.SplitHostPort(addr)
		if e != nil {
			return nil, e
		}
		if port != "80" && port != "443" {
			return nil, ErrForbidden
		}
		ips, e := resolvePublic(ctx, host)
		if e != nil {
			return nil, e
		}
		var last error
		for _, ip := range ips {
			c, e := (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, "tcp", net.JoinHostPort(ip.IP.String(), port))
			if e == nil {
				return c, nil
			}
			last = e
		}
		return nil, last
	}}
	return &http.Client{Timeout: 5 * time.Second, Transport: tr, CheckRedirect: func(r *http.Request, via []*http.Request) error {
		if len(via) >= 3 {
			return ErrForbidden
		}
		_, e := previewURL(r.URL.String())
		return e
	}}
}
func trimPreview(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > n {
		s = s[:n]
		for !utf8.ValidString(s) {
			s = s[:len(s)-1]
		}
	}
	return s
}
func parsePreview(raw string, reader io.Reader) (LinkPreview, error) {
	doc, e := html.Parse(reader)
	if e != nil {
		return LinkPreview{}, e
	}
	p := LinkPreview{URL: raw, FetchedAt: time.Now().Unix()}
	var title string
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode && n.Data == "meta" {
			key, content := "", ""
			for _, at := range n.Attr {
				if at.Key == "property" || at.Key == "name" {
					key = strings.ToLower(at.Val)
				}
				if at.Key == "content" {
					content = at.Val
				}
			}
			switch key {
			case "og:title":
				p.Title = content
			case "og:description":
				p.Description = content
			case "description":
				if p.Description == "" {
					p.Description = content
				}
			case "og:image":
				p.Image = content
			case "og:site_name":
				p.SiteName = content
			}
		}
		if n.Type == html.ElementNode && n.Data == "title" && n.FirstChild != nil {
			title = n.FirstChild.Data
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)
	if p.Title == "" {
		p.Title = title
	}
	p.Title = trimPreview(p.Title, 500)
	p.Description = trimPreview(p.Description, 1500)
	p.SiteName = trimPreview(p.SiteName, 200)
	if p.Image != "" {
		base, _ := url.Parse(raw)
		rel, e := url.Parse(p.Image)
		if e != nil {
			p.Image = ""
		} else {
			u := base.ResolveReference(rel)
			if _, e = previewURL(u.String()); e != nil {
				p.Image = ""
			} else {
				p.Image = u.String()
			}
		}
	}
	return p, nil
}
func fetchPreview(ctx context.Context, raw string) (LinkPreview, error) {
	u, e := previewURL(raw)
	if e != nil {
		return LinkPreview{}, e
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	client := previewClient()
	defer client.CloseIdleConnections()
	r, _ := http.NewRequestWithContext(ctx, "GET", u.String(), nil)
	r.Header.Set("User-Agent", "QuietChat-LinkPreview/1.0")
	r.Header.Set("Accept", "text/html")
	res, e := client.Do(r)
	if e != nil {
		return LinkPreview{}, ErrForbidden
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		return LinkPreview{}, ErrInvalid
	}
	if ct := res.Header.Get("Content-Type"); ct != "" && !strings.Contains(ct, "text/html") {
		return LinkPreview{}, ErrInvalid
	}
	if l, _ := strconv.ParseInt(res.Header.Get("Content-Length"), 10, 64); l > 512<<10 {
		return LinkPreview{}, ErrInvalid
	}
	b, e := io.ReadAll(io.LimitReader(res.Body, (512<<10)+1))
	if e != nil || len(b) > 512<<10 {
		return LinkPreview{}, ErrInvalid
	}
	p, e := parsePreview(res.Request.URL.String(), strings.NewReader(string(b)))
	if e != nil {
		return p, e
	}
	p.URL = u.String()
	if p.Image != "" {
		im, _ := url.Parse(p.Image)
		if _, e = resolvePublic(ctx, im.Hostname()); e != nil {
			p.Image = ""
		}
	}
	return p, nil
}
func (a *App) preview(w http.ResponseWriter, r *http.Request, p Principal) {
	if !a.limiter.allow("preview:"+p.UserID, 10, time.Minute) {
		respond(w, 429, map[string]string{"error": "rate_limited"})
		return
	}
	var b struct {
		URL string `json:"url"`
	}
	if !decode(w, r, &b) {
		return
	}
	u, e := previewURL(b.URL)
	if e != nil {
		fail(w, e)
		return
	}
	raw := u.String()
	var out LinkPreview
	e = a.DB.QueryRow("SELECT id,url,title,description,image,site_name,fetched_at FROM link_previews WHERE url=? AND fetched_at>?", raw, time.Now().Add(-24*time.Hour).Unix()).Scan(&out.ID, &out.URL, &out.Title, &out.Description, &out.Image, &out.SiteName, &out.FetchedAt)
	if e == nil {
		respond(w, 200, out)
		return
	}
	if e != sql.ErrNoRows {
		fail(w, e)
		return
	}
	out, e = fetchPreview(r.Context(), raw)
	if e != nil {
		fail(w, e)
		return
	}
	out.ID = id()
	_, e = a.DB.Exec("INSERT INTO link_previews(id,url,title,description,image,site_name,fetched_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(url) DO UPDATE SET title=excluded.title,description=excluded.description,image=excluded.image,site_name=excluded.site_name,fetched_at=excluded.fetched_at", out.ID, out.URL, out.Title, out.Description, out.Image, out.SiteName, out.FetchedAt)
	if e != nil {
		fail(w, e)
		return
	}
	a.DB.QueryRow("SELECT id FROM link_previews WHERE url=?", raw).Scan(&out.ID)
	respond(w, 200, out)
}
func previewForSend(tx *sql.Tx, s Send) (*LinkPreview, error) {
	if s.LinkPreviewID == "" {
		return nil, nil
	}
	var p LinkPreview
	e := tx.QueryRow("SELECT id,url,title,description,image,site_name,fetched_at FROM link_previews WHERE id=?", s.LinkPreviewID).Scan(&p.ID, &p.URL, &p.Title, &p.Description, &p.Image, &p.SiteName, &p.FetchedAt)
	if e != nil {
		return nil, ErrInvalid
	}
	found := strings.Contains(s.Text, p.URL)
	for _, ent := range s.Entities {
		if ent.Type == "text_link" && ent.URL == p.URL {
			found = true
		}
	}
	if !found {
		return nil, ErrInvalid
	}
	return &p, nil
}
