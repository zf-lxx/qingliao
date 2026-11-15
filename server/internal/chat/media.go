package chat

import (
	"bytes"
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

var (
	errFileTooLarge     = errors.New("file_too_large")
	errMediaQuota       = errors.New("media_quota_exceeded")
	errUploadFailed     = errors.New("file_too_large_or_upload_failed")
	errUnsupportedMedia = errors.New("unsupported media type")
)

type mediaStoreOpts struct {
	Owner       string
	ChatID      string
	FileName    string
	Width       int
	Height      int
	DurationMs  int
	Waveform    string
	ThumbnailID string
	Require     string
	// DeclaredMIME is the type the client claims for the body. It is only used
	// when it agrees with the sniffed container family; see storeMedia.
	DeclaredMIME string
}

func (a *App) storeMedia(ctx context.Context, r io.Reader, opts mediaStoreOpts) (MediaInfo, error) {
	var out MediaInfo
	if r == nil {
		return out, ErrInvalid
	}
	a.mediaMu.Lock()
	defer a.mediaMu.Unlock()
	used, e := a.storage.Usage(ctx)
	if e != nil {
		return out, e
	}
	limit := a.C.MaxFile
	if remaining := a.C.MediaQuota - used; remaining < limit {
		limit = remaining
	}
	if limit <= 0 {
		return out, errMediaQuota
	}
	sniffSize := int64(512)
	if limit+1 < sniffSize {
		sniffSize = limit + 1
	}
	head := make([]byte, sniffSize)
	n, e := io.ReadFull(r, head)
	if e != nil && e != io.EOF && e != io.ErrUnexpectedEOF {
		return out, ErrInvalid
	}
	head = head[:n]
	if int64(n) > limit {
		return out, errFileTooLarge
	}
	if n == 0 {
		return out, ErrInvalid
	}
	// A client-supplied MIME wins over sniffing, because sniffing cannot
	// separate formats that share a container header (an m4a voice memo and an
	// mp4 video both start with an ftyp box and both sniff as video/mp4).
	// The declared type never overrides the rejection of active content: the
	// sniffed type is still checked for html/xml/svg first, and a declaration
	// is only honoured when it agrees with the container family.
	sniffed := sniffMedia(head, http.DetectContentType(head))
	mime := sniffed
	if opts.DeclaredMIME != "" && validDeclaredMime(opts.DeclaredMIME) && mimeFamilyMatches(opts.DeclaredMIME, sniffed) {
		mime = strings.ToLower(opts.DeclaredMIME)
	}
	if strings.Contains(mime, "html") || strings.Contains(mime, "xml") || strings.Contains(mime, "svg") {
		return out, ErrInvalid
	}
	if strings.HasPrefix(mime, "text/") {
		mime = "application/octet-stream"
	}
	if opts.Require != "" && !mediaMatches(opts.Require, mime) {
		return out, errUnsupportedMedia
	}
	mid := id()
	digest := sha256.New()
	reader := io.TeeReader(io.MultiReader(bytes.NewReader(head), r), digest)
	n64, e := a.storage.Put(ctx, mid, io.LimitReader(reader, limit+1))
	if e != nil || n64 > limit {
		a.storage.Delete(ctx, mid)
		return out, errUploadFailed
	}
	if opts.ChatID != "" && opts.Owner != "" && !a.isMember(opts.ChatID, opts.Owner) {
		a.storage.Delete(ctx, mid)
		return out, ErrForbidden
	}
	if opts.ThumbnailID != "" {
		var tmime string
		e = a.DB.QueryRow("SELECT mime FROM media WHERE id=? AND owner=?", opts.ThumbnailID, opts.Owner).Scan(&tmime)
		if e != nil || !strings.HasPrefix(tmime, "image/") || opts.ThumbnailID == mid {
			a.storage.Delete(ctx, mid)
			return out, ErrInvalid
		}
	}
	fileName := sanitizeFileName(opts.FileName)
	_, e = a.DB.Exec("INSERT INTO media(id,owner,chat_id,mime,bytes,sha256,created,width,height,duration_ms,waveform,file_name,thumbnail_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", mid, opts.Owner, opts.ChatID, mime, n64, hex.EncodeToString(digest.Sum(nil)), now(), opts.Width, opts.Height, opts.DurationMs, opts.Waveform, fileName, opts.ThumbnailID)
	if e != nil {
		a.storage.Delete(ctx, mid)
		return out, e
	}
	out = MediaInfo{ID: mid, MIME: mime, Bytes: n64, Width: opts.Width, Height: opts.Height, DurationMs: opts.DurationMs, Waveform: opts.Waveform, FileName: fileName, ThumbnailID: opts.ThumbnailID}
	return out, nil
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
	meta, e := parseMediaHeaders(r)
	if e != nil {
		fail(w, e)
		return
	}
	// Raw body (not multipart); stream limit+1 directly to disk, never buffer file.
	r.Body = http.MaxBytesReader(w, r.Body, a.C.MaxFile+1)
	defer r.Body.Close()
	info, e := a.storeMedia(r.Context(), r.Body, mediaStoreOpts{
		Owner: p.UserID, ChatID: cid, FileName: meta.FileName,
		Width: meta.Width, Height: meta.Height, DurationMs: meta.DurationMs,
		Waveform: meta.Waveform, ThumbnailID: meta.ThumbnailID,
		DeclaredMIME: meta.MIME,
	})
	if e != nil {
		switch {
		case errors.Is(e, errMediaQuota):
			respond(w, 507, map[string]string{"error": "media_quota_exceeded"})
		case errors.Is(e, errFileTooLarge):
			respond(w, 413, map[string]string{"error": "file_too_large"})
		case errors.Is(e, errUploadFailed):
			respond(w, 413, map[string]string{"error": "file_too_large_or_upload_failed"})
		default:
			fail(w, e)
		}
		return
	}
	// Recompute digest hash for the response from the stored row.
	var sha string
	_ = a.DB.QueryRow("SELECT sha256 FROM media WHERE id=?", info.ID).Scan(&sha)
	respond(w, 201, map[string]any{"id": info.ID, "mime": info.MIME, "bytes": info.Bytes, "sha256": sha, "storage": "local", "width": info.Width, "height": info.Height, "duration_ms": info.DurationMs, "waveform": info.Waveform, "file_name": info.FileName, "thumbnail_id": info.ThumbnailID})
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
		e = a.DB.QueryRow(`SELECT (SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.media_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0)+(SELECT count(*) FROM users WHERE avatar=?)+(SELECT count(*) FROM chats WHERE avatar=?)+(SELECT count(*) FROM messages m JOIN media x ON x.id=m.media_id JOIN members b ON b.chat_id=m.chat_id WHERE x.thumbnail_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0)+(SELECT count(*) FROM stickers WHERE media_id=?)+(SELECT count(*) FROM stories WHERE media_id=? AND deleted=0 AND expires>unixepoch())`, mid, p.UserID, mid, mid, mid, p.UserID, mid, mid).Scan(&allowed)
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
	a.DB.QueryRow("SELECT (SELECT count(*) FROM messages WHERE media_id=? AND deleted=0)+(SELECT count(*) FROM users WHERE avatar=?)+(SELECT count(*) FROM chats WHERE avatar=?)+(SELECT count(*) FROM media WHERE thumbnail_id=?)+(SELECT count(*) FROM stickers WHERE media_id=?)+(SELECT count(*) FROM stories WHERE media_id=?)", mid, mid, mid, mid, mid, mid).Scan(&refs)
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

// mimeFamilyMatches reports whether a client-declared MIME may replace the
// sniffed one.
//
// sniffing works on the first bytes only, so it cannot separate formats that
// share a container: an m4a voice memo and an mp4 video both start with an
// ftyp box and both sniff as video/mp4, and an mp4 can be audio-only. audio/
// and video/ are therefore treated as one family for declaration purposes.
// image/ never mixes with them, so a declaration cannot turn arbitrary bytes
// into a renderable image.
func mimeFamilyMatches(declared, sniffed string) bool {
	declared = strings.ToLower(declared)
	sniffed = strings.ToLower(sniffed)
	// An octet-stream sniff carries no family information, so any valid
	// declaration is an improvement on it. The html/xml/svg rejection above
	// already ran on the sniffed value for the declared case.
	if sniffed == "application/octet-stream" {
		return true
	}
	return mimeFamily(declared) == mimeFamily(sniffed)
}

func mimeFamily(mime string) string {
	switch {
	case strings.HasPrefix(mime, "audio/"), strings.HasPrefix(mime, "video/"):
		return "av"
	case strings.HasPrefix(mime, "image/"):
		return "image"
	default:
		return mime
	}
}
