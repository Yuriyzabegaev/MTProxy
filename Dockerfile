# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        build-essential \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY . ./

RUN make -j"$(nproc)" \
    && strip objs/bin/mtproto-proxy

# ── Stage 2: runtime ────────────────────────────────────────────────────────
FROM debian:bookworm-slim

# Only the shared libs the binary actually needs at runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        libssl3 \
        zlib1g \
        curl \
        xxd \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Drop privileges: run as a dedicated non-root user
RUN useradd -r -s /sbin/nologin -d /opt/mtproxy mtproxy

WORKDIR /opt/mtproxy

COPY --from=builder /build/objs/bin/mtproto-proxy .

# Runtime tunables.
ENV PORT=443 \
    LOCAL_PORT=8888 \
    WORKERS=1 \
    TAG=""

COPY entrypoint.sh /opt/mtproxy/entrypoint.sh
RUN chmod +x /opt/mtproxy/entrypoint.sh \
    && chown -R mtproxy:mtproxy /opt/mtproxy

USER mtproxy

# Clients connect on $PORT; stats available on $LOCAL_PORT (loopback only)
EXPOSE 443
EXPOSE 8888

ENTRYPOINT ["/opt/mtproxy/entrypoint.sh"]