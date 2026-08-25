#!/usr/bin/env bash
# Decode the payload of a JWT. Reads token from $1 or $TOKEN.
set -euo pipefail

JWT="${1:-${TOKEN:-}}"
if [ -z "$JWT" ]; then
    echo "Usage: $0 <jwt>   (or set \$TOKEN)" >&2
    exit 1
fi

python3 <<EOF
import base64, json, sys
payload = "$JWT".split(".")[1]
payload += "=" * (-len(payload) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
EOF
