# -- Build --
FROM golang:1.27.1-alpine AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o cove ./cmd/cove

# -- Test --
# Lighthouse builds this stage before deploying Cove: a failure stops the
# deploy. The database integration tests skip here (no Postgres).
FROM builder AS test
RUN apk add --no-cache gcc musl-dev
RUN unformatted="$(gofmt -l .)" && [ -z "$unformatted" ] || { echo "These files need gofmt:"; echo "$unformatted"; exit 1; }
RUN go vet ./...
RUN CGO_ENABLED=1 go test -race -count=1 ./...

# -- Final --
# Pinned, so a rebuild gets the same base as before. Bump it on purpose
# (e.g. to pick up security fixes): alpine:3.24 follows 3.24.x patch releases.
FROM alpine:3.24
WORKDIR /app

# Cove runs as an ordinary user, not root. The user exists only inside the
# image; the host needs no account for it, but the bind-mounted files must be
# owned by it:  chown -R 10001:10001 /srv/server/storage/cove
RUN adduser -D -H -u 10001 cove

COPY --from=builder /app/cove /cove

USER 10001:10001

EXPOSE 2100
# API server only; open the CLI with `docker exec -it <container> /cove shell`.
CMD ["/cove", "serve"]
