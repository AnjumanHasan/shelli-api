#!/usr/bin/env bash
# Obtain an Auth0 access token via OAuth2 Device Authorization Grant.
# Used for testing the gateway from curl without writing a CLI yet.

set -euo pipefail

DOMAIN="dev-fwnv1luqf2t1yke0.us.auth0.com"
CLIENT_ID="ziknYEMEkMTaCjkV8M6qTe05htGqds1K"
AUDIENCE="https://api.shelli.local"

command -v jq >/dev/null || { echo "jq is required: brew install jq" >&2; exit 1; }

echo "Requesting device code..."
RESP=$(curl -sS -X POST "https://$DOMAIN/oauth/device/code" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID" \
    -d "audience=$AUDIENCE" \
    -d "scope=openid email profile")

if echo "$RESP" | jq -e '.error' >/dev/null 2>&1; then
    echo "Auth0 rejected the device-code request:"
    echo "$RESP" | jq
    exit 1
fi

DEVICE_CODE=$(echo "$RESP" | jq -r .device_code)
USER_CODE=$(echo "$RESP" | jq -r .user_code)
VERIFICATION_URI_COMPLETE=$(echo "$RESP" | jq -r .verification_uri_complete)
INTERVAL=$(echo "$RESP" | jq -r .interval)

cat <<EOF

────────────────────────────────────────────────
  Open this URL in your browser:
    $VERIFICATION_URI_COMPLETE

  Or visit https://$DOMAIN/activate
  and enter the code:  $USER_CODE
────────────────────────────────────────────────

EOF

if command -v open >/dev/null; then
    open "$VERIFICATION_URI_COMPLETE" 2>/dev/null || true
fi

echo -n "Waiting for authorization"
while true; do
    sleep "$INTERVAL"
    POLL=$(curl -fsS -X POST "https://$DOMAIN/oauth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
        -d "device_code=$DEVICE_CODE" \
        -d "client_id=$CLIENT_ID" 2>/dev/null || true)

    ERROR=$(echo "$POLL" | jq -r '.error // empty')
    if [ -z "$ERROR" ]; then
        ACCESS_TOKEN=$(echo "$POLL" | jq -r .access_token)
        echo ""
        echo "Authorized."
        echo ""
        echo "$ACCESS_TOKEN"
        echo ""
        echo "Tip:  export SHELLI_TOKEN=\$(./scripts/get-token.sh | tail -3 | head -1)" >&2
        exit 0
    fi

    case "$ERROR" in
        authorization_pending|slow_down) echo -n "." ;;
        *) echo ""; echo "Error: $POLL" >&2; exit 1 ;;
    esac
done
