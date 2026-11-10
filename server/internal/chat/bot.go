package chat

import "context"

// Bot API is a future extension, NOT an implemented/public route. Bot tokens
// must be separately scoped/hashed and never reuse human session credentials.
type BotIdentity struct {
	ID, OwnerID, Username string
	Scopes                []string
}
type BotUpdate struct {
	UpdateID int64
	Event    Event
}
type BotGateway interface {
	AuthenticateBot(context.Context, string) (BotIdentity, error)
	GetUpdates(context.Context, BotIdentity, int64, int) ([]BotUpdate, error)
	SetWebhook(context.Context, BotIdentity, string, string) error
	SendMessage(context.Context, BotIdentity, string, Send) (Message, error)
}
