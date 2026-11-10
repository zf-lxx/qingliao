# syntax=docker/dockerfile:1
FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/quietchat ./cmd/server && mkdir -p /out/data && chown 65532:65532 /out/data && chmod 700 /out/data
FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /out/quietchat /quietchat
COPY --from=build --chown=65532:65532 /out/data /data
USER 65532:65532
ENV CHAT_ADDR=0.0.0.0:8088 CHAT_DATA=/data GOMEMLIMIT=64MiB
EXPOSE 8088
ENTRYPOINT ["/quietchat"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s CMD ["/quietchat","healthcheck"]
