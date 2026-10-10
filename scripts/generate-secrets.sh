#!/bin/bash
set -euo pipefail

plain=$(openssl rand -base64 96 | tr -dc 'a-zA-Z0-9' | head -c 64)
salt=$(openssl rand -base64 16)
hash=$(echo -n "$plain" | argon2 "$salt" -e -id -k 65536 -t 3 -p 4)

echo "Plain: $plain"
echo "Hash:  $hash"
