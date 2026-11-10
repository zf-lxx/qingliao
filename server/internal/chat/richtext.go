package chat

import (
	"net/url"
	"sort"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

type Entity struct {
	Type          string `json:"type"`
	Offset        int    `json:"offset"`
	Length        int    `json:"length"`
	URL           string `json:"url,omitempty"`
	Language      string `json:"language,omitempty"`
	CustomEmojiID string `json:"custom_emoji_id,omitempty"`
}
type InlineButton struct {
	Text         string `json:"text"`
	URL          string `json:"url,omitempty"`
	CallbackData string `json:"callback_data,omitempty"`
}
type ReplyMarkup struct {
	InlineKeyboard [][]InlineButton `json:"inline_keyboard"`
}

func safeURL(raw string) (*url.URL, error) {
	u, e := url.Parse(raw)
	if e != nil || len(raw) > 2048 || u.Hostname() == "" || u.User != nil || (u.Scheme != "https" && u.Scheme != "http") {
		return nil, ErrInvalid
	}
	if strings.ContainsAny(raw, "\r\n\x00") {
		return nil, ErrInvalid
	}
	return u, nil
}
func validateEntities(text string, entities []Entity) ([]Entity, error) {
	if !utf8.ValidString(text) || len(entities) > 128 {
		return nil, ErrInvalid
	}
	units := utf16.Encode([]rune(text))
	boundary := map[int]bool{0: true}
	pos := 0
	for _, r := range text {
		pos += utf16.RuneLen(r)
		boundary[pos] = true
	}
	out := append([]Entity(nil), entities...)
	sort.Slice(out, func(i, j int) bool {
		if out[i].Offset != out[j].Offset {
			return out[i].Offset < out[j].Offset
		}
		if out[i].Length != out[j].Length {
			return out[i].Length > out[j].Length
		}
		return out[i].Type < out[j].Type
	})
	for i, e := range out {
		if e.Offset < 0 || e.Length <= 0 || e.Offset > len(units) || e.Length > len(units)-e.Offset || !boundary[e.Offset] || !boundary[e.Offset+e.Length] {
			return nil, ErrInvalid
		}
		switch e.Type {
		case "bold", "italic", "underline", "strikethrough", "code", "pre", "blockquote", "spoiler", "text_link", "url", "mention", "hashtag", "custom_emoji":
		default:
			return nil, ErrInvalid
		}
		if e.Type == "text_link" {
			if _, err := safeURL(e.URL); err != nil {
				return nil, err
			}
		} else if e.URL != "" {
			return nil, ErrInvalid
		}
		if e.Type == "url" {
			if _, err := safeURL(string(utf16.Decode(units[e.Offset : e.Offset+e.Length]))); err != nil {
				return nil, err
			}
		}
		if e.Type != "pre" && e.Language != "" {
			return nil, ErrInvalid
		}
		if len(e.Language) > 32 {
			return nil, ErrInvalid
		}
		for _, r := range e.Language {
			if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune(".+#_-", r)) {
				return nil, ErrInvalid
			}
		}
		if e.Type == "custom_emoji" {
			if e.CustomEmojiID == "" || len(e.CustomEmojiID) > 128 {
				return nil, ErrInvalid
			}
		} else if e.CustomEmojiID != "" {
			return nil, ErrInvalid
		}
		for j := 0; j < i; j++ {
			p := out[j]
			if p.Offset+p.Length <= e.Offset {
				continue
			}
			if p.Offset == e.Offset && p.Length == e.Length && p.Type == e.Type {
				return nil, ErrInvalid
			}
			if e.Offset+e.Length > p.Offset+p.Length {
				return nil, ErrInvalid
			}
			if p.Type == "code" || p.Type == "pre" || e.Type == "code" || e.Type == "pre" {
				return nil, ErrInvalid
			}
			link := func(t string) bool { return t == "text_link" || t == "url" || t == "mention" || t == "hashtag" }
			if link(p.Type) && link(e.Type) {
				return nil, ErrInvalid
			}
			if p.Type == "blockquote" && e.Type == "blockquote" {
				return nil, ErrInvalid
			}
		}
	}
	return out, nil
}
func validateMarkup(m *ReplyMarkup) error {
	if m == nil {
		return nil
	}
	if len(m.InlineKeyboard) < 1 || len(m.InlineKeyboard) > 8 {
		return ErrInvalid
	}
	total := 0
	for _, row := range m.InlineKeyboard {
		if len(row) < 1 || len(row) > 8 {
			return ErrInvalid
		}
		for _, b := range row {
			total++
			if len(b.Text) < 1 || len(b.Text) > 256 || !utf8.ValidString(b.Text) || (b.URL == "") == (b.CallbackData == "") {
				return ErrInvalid
			}
			if b.URL != "" {
				if _, e := safeURL(b.URL); e != nil {
					return e
				}
			}
			if len(b.CallbackData) > 64 || !utf8.ValidString(b.CallbackData) {
				return ErrInvalid
			}
		}
	}
	if total > 64 {
		return ErrInvalid
	}
	return nil
}
