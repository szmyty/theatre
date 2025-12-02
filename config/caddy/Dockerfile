# Build Caddy with DuckDNS module for automatic HTTPS via DNS-01 challenge
FROM caddy:2.8.4-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/duckdns

FROM caddy:2.8.4

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
