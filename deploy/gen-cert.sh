#!/usr/bin/env bash
# Generates a self-signed TLS certificate for the server IP.
set -euo pipefail
HOST="${1:-172.14.50.81}"
DIR="$(cd "$(dirname "$0")" && pwd)/certs"
mkdir -p "$DIR"
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout "$DIR/server.key" -out "$DIR/server.crt" \
  -subj "/CN=$HOST" -addext "subjectAltName=IP:$HOST"
echo "Certificate written to $DIR"
