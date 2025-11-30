# Build Caddy with DuckDNS module for automatic HTTPS via DNS-01 challenge
FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/duckdns

FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
