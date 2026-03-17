#!/bin/sh
set -e

WORKDIR=/opt/mtproxy
cd "$WORKDIR"

echo "[*] Fetching proxy-secret ..."
curl -sSf https://core.telegram.org/getProxySecret -o proxy-secret

echo "[*] Fetching proxy-multi.conf ..."
curl -sSf https://core.telegram.org/getProxyConfig -o proxy-multi.conf

# Refresh proxy-multi.conf once per day in the background.
# mtproto-proxy re-reads the file automatically; no restart needed.
(
    while true; do
        sleep 86400
        echo "[*] Refreshing proxy-multi.conf ..."
        curl -sSf https://core.telegram.org/getProxyConfig -o proxy-multi.conf \
            && echo "[*] proxy-multi.conf updated." \
            || echo "[!] Failed to refresh proxy-multi.conf – keeping previous version."
    done
) &

# Build -S flags from space-separated SECRET env var
if [ -z "$SECRET" ]; then
    echo "[*] No SECRET provided – generating one ..."
    SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    echo "[*] Generated secret: $SECRET"
fi

SECRET_FLAGS=""
for s in $SECRET; do
    SECRET_FLAGS="$SECRET_FLAGS -S $s"
done

# Optional proxy tag
TAG_FLAG=""
if [ -n "$TAG" ]; then
    TAG_FLAG="-P $TAG"
fi

# NAT: detect internal vs external IP automatically.
# The binary reports its internal Docker IP to Telegram, which then
# tells clients to connect to an unreachable address. We must tell
# it the real external IP explicitly.
INTERNAL_IP=$(hostname -i | awk '{print $1}')
EXTERNAL_IP=$(curl -sSf https://api.ipify.org)
echo "[*] NAT: internal=$INTERNAL_IP external=$EXTERNAL_IP"
NAT_FLAG="--nat-info ${INTERNAL_IP}:${EXTERNAL_IP}"

echo "[*] Starting mtproto-proxy on port $PORT with $WORKERS worker(s) ..."
exec ./mtproto-proxy \
    -H "$PORT" \
    -p "$LOCAL_PORT" \
    --http-stats \
    $SECRET_FLAGS \
    $TAG_FLAG \
    $NAT_FLAG \
    --aes-pwd proxy-secret proxy-multi.conf \
    -M "$WORKERS"