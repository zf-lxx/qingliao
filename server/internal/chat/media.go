package chat

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var ErrNotSupported = errors.New("storage operation not supported")

// R2/S3 adapter can implement this contract; unimplemented modes fail closed.
type Storage interface {
	Put(context.Context, string, io.Reader) (int64, error)
	Open(context.Context, string) (ReadSeekCloser, error)
	Delete(context.Context, string) error
	Usage(context.Context) (int64, error)
	PresignUpload(context.Context, string, time.Duration) (string, error)
}
type ReadSeekCloser interface {
	io.Reader
	io.Seeker
	io.Closer
}
type LocalStorage struct{ root string }

var keyRE = regexp.MustCompile(`^[a-f0-9]{32}$`)

func NewLocalStorage(root string) (Storage, error) {
	if e := os.MkdirAll(root, 0700); e != nil {
		return nil, e
	}
	return &LocalStorage{root}, nil
}
func (s *LocalStorage) path(key string) (string, error) {
	if !keyRE.MatchString(key) {
		return "", ErrInvalid
	}
	return filepath.Join(s.root, key), nil
}
func (s *LocalStorage) Put(ctx context.Context, key string, r io.Reader) (int64, error) {
	path, e := s.path(key)
	if e != nil {
		return 0, e
	}
	f, e := os.CreateTemp(s.root, ".upload-")
	if e != nil {
		return 0, e
	}
	defer os.Remove(f.Name())
	n, e := io.Copy(f, r)
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e == nil {
		e = ce
	}
	if e == nil {
		e = os.Rename(f.Name(), path)
	}
	return n, e
}
func (s *LocalStorage) Open(ctx context.Context, key string) (ReadSeekCloser, error) {
	p, e := s.path(key)
	if e != nil {
		return nil, e
	}
	return os.Open(p)
}
func (s *LocalStorage) Delete(ctx context.Context, key string) error {
	p, e := s.path(key)
	if e != nil {
		return e
	}
	e = os.Remove(p)
	if os.IsNotExist(e) {
		return nil
	}
	return e
}
func (s *LocalStorage) Usage(ctx context.Context) (int64, error) {
	var bytes int64
	e := filepath.WalkDir(s.root, func(p string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		if !d.IsDir() {
			i, e := d.Info()
			if e != nil {
				return e
			}
			bytes += i.Size()
		}
		return ctx.Err()
	})
	return bytes, e
}
func (s *LocalStorage) PresignUpload(context.Context, string, time.Duration) (string, error) {
	return "", ErrNotSupported
}
func (a *App) upload(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.Header.Get("X-Conversation-ID")
	if cid != "" && !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	if cid != "" {
		if e := a.uploadPermission(p, cid); e != nil {
			fail(w, e)
			return
		}
	}
	a.mediaMu.Lock()
	defer a.mediaMu.Unlock()
	used, e := a.storage.Usage(r.Context())
	if e != nil {
		fail(w, e)
		return
	}
	limit := a.C.MaxFile
	if remaining := a.C.MediaQuota - used; remaining < limit {
		limit = remaining
	}
	if limit <= 0 {
		respond(w, 507, map[string]string{"error": "media_quota_exceeded"})
		return
	}
	// Raw body (not multipart); stream limit+1 directly to disk, never buffer file.
	r.Body = http.MaxBytesReader(w, r.Body, limit+1)
	defer r.Body.Close()
	sniffSize := int64(512)
	if limit+1 < sniffSize {
		sniffSize = limit + 1
	}
	head := make([]byte, sniffSize)
	n, e := io.ReadFull(r.Body, head)
	if e != nil && e != io.EOF && e != io.ErrUnexpectedEOF {
		fail(w, ErrInvalid)
		return
	}
	head = head[:n]
	if int64(n) > limit {
		respond(w, 413, map[string]string{"error": "file_too_large"})
		return
	}
	if n == 0 {
		fail(w, ErrInvalid)
		return
	}
	mime := http.DetectContentType(head)
	if mime == "application/ogg" {
		mime = "audio/ogg"
	}
	if strings.Contains(mime, "html") || strings.Contains(mime, "xml") || strings.Contains(mime, "svg") {
		fail(w, ErrInvalid)
		return
	}
	if strings.HasPrefix(mime, "text/") {
		mime = "application/octet-stream"
	}
	mid := id()
	digest := sha256.New()
	reader := io.TeeReader(io.MultiReader(strings.NewReader(string(head)), r.Body), digest)
	n64, e := a.storage.Put(r.Context(), mid, io.LimitReader(reader, limit+1))
	if e != nil || n64 > limit {
		a.storage.Delete(r.Context(), mid)
		respond(w, 413, map[string]string{"error": "file_too_large_or_upload_failed"})
		return
	}
	// Membership can change while upload streams; validate again before publishing metadata.
	if cid != "" && !a.isMember(cid, p.UserID) {
		a.storage.Delete(r.Context(), mid)
		fail(w, ErrForbidden)
		return
	}
	_, e = a.DB.Exec("INSERT INTO media(id,owner,chat_id,mime,bytes,sha256,created) VALUES(?,?,?,?,?,?,?)", mid, p.UserID, cid, mime, n64, hex.EncodeToString(digest.Sum(nil)), now())
	if e != nil {
		a.storage.Delete(r.Context(), mid)
		fail(w, e)
		return
	}
	respond(w, 201, map[string]any{"id": mid, "mime": mime, "bytes": n64, "sha256": hex.EncodeToString(digest.Sum(nil)), "storage": "local"})
}
func (a *App) download(w http.ResponseWriter, r *http.Request, p Principal) {
	mid := r.PathValue("id")
	var owner, mime, created string
	var bytes int64
	e := a.DB.QueryRow("SELECT owner,mime,bytes,created FROM media WHERE id=?", mid).Scan(&owner, &mime, &bytes, &created)
	if e != nil {
		fail(w, ErrForbidden)
		return
	}
	if owner != p.UserID {
		var allowed int
		e = a.DB.QueryRow(`SELECT (SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.media_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0)+(SELECT count(*) FROM users WHERE avatar=?)`, mid, p.UserID, mid).Scan(&allowed)
		if e != nil || allowed == 0 {
			fail(w, ErrForbidden)
			return
		}
	}
	f, e := a.storage.Open(r.Context(), mid)
	if e != nil {
		fail(w, e)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", mid))
	w.Header().Set("Content-Security-Policy", "sandbox; default-src 'none'")
	w.Header().Set("Cache-Control", "private, no-store")
	t, _ := time.Parse(time.RFC3339Nano, created)
	http.ServeContent(w, r, mid, t, f)
}
func (a *App) deleteMedia(w http.ResponseWriter, r *http.Request, p Principal) {
	a.mediaMu.Lock()
	defer a.mediaMu.Unlock()
	mid := r.PathValue("id")
	var n int
	e := a.DB.QueryRow("SELECT count(*) FROM media WHERE id=? AND owner=?", mid, p.UserID).Scan(&n)
	if e != nil || n != 1 {
		fail(w, ErrForbidden)
		return
	}
	var refs int
	a.DB.QueryRow("SELECT (SELECT count(*) FROM messages WHERE media_id=? AND deleted=0)+(SELECT count(*) FROM users WHERE avatar=?)", mid, mid).Scan(&refs)
	if refs > 0 {
		fail(w, ErrConflict)
		return
	}
	if e = a.storage.Delete(r.Context(), mid); e != nil {
		fail(w, e)
		return
	}
	_, e = a.DB.Exec("DELETE FROM media WHERE id=?", mid)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
