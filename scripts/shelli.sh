#!/usr/bin/env bash
# shelli — turn plain English into a shell command.
#
#   shelli copy myfile.txt from src to dest and rename it backup.txt
#
# Talks to the shelli-gateway proxy, which holds the LLM key and validates
# the generated command. This client validates a second time before running
# anything (dual-layer safety), because the proxy's answer comes from an LLM.

set -uo pipefail

VERSION="0.1.0"

CONFIG_DIR="${SHELLI_CONFIG_DIR:-$HOME/.shelli}"
CONFIG_FILE="$CONFIG_DIR/config"
TOKEN_FILE="$CONFIG_DIR/token"

# Precedence is environment > config file > default, so capture whatever the
# environment gave us before sourcing the config file can overwrite it.
ENV_API_URL="${SHELLI_API_URL:-}"
ENV_MODE="${SHELLI_MODE:-}"
ENV_AUTH0_DOMAIN="${SHELLI_AUTH0_DOMAIN:-}"
ENV_AUTH0_CLIENT_ID="${SHELLI_AUTH0_CLIENT_ID:-}"
ENV_AUDIENCE="${SHELLI_AUDIENCE:-}"

# ── output helpers ────────────────────────────────────────────────────────────

if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

die()  { printf '%sshelli:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
info() { printf '%s%s%s\n' "$DIM" "$*" "$RESET" >&2; }

usage() {
    cat <<EOF
${BOLD}shelli${RESET} — plain English to shell commands (v$VERSION)

${BOLD}USAGE${RESET}
  shelli <what you want to do>
  shelli <command>

${BOLD}COMMANDS${RESET}
  login             Sign in via Auth0 device flow and cache the token
  logout            Delete the cached token
  whoami            Show the identity the gateway sees (GET /api/me)
  config            Print the resolved configuration
  help              Show this help

${BOLD}OPTIONS${RESET}
  -d, --display     Print the command only; never offer to run it
  -i, --interactive Ask before running (default)
  -y, --yes         Run without asking (refused for unsafe commands)
  -v, --version     Print version

${BOLD}EXAMPLES${RESET}
  shelli find all files larger than 100MB under my home directory
  shelli -d show me the last 20 lines of every log in /var/log
  shelli grep TODO in src and show the last modified time of each match

${BOLD}CONFIG${RESET}
  $CONFIG_FILE  (shell syntax, e.g. SHELLI_API_URL=https://...)
    SHELLI_API_URL    gateway base URL      [$SHELLI_API_URL]
    SHELLI_MODE       interactive|display   [$SHELLI_MODE]
  Environment variables of the same name win over the config file.

${BOLD}NOTE${RESET}
  Commands run in a subshell, so effects on the current shell (cd, export)
  do not persist. For those, copy the printed command instead.
EOF
}

# ── config ────────────────────────────────────────────────────────────────────

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
    SHELLI_API_URL="${ENV_API_URL:-${SHELLI_API_URL:-http://localhost:8080}}"
    SHELLI_MODE="${ENV_MODE:-${SHELLI_MODE:-interactive}}"
    SHELLI_AUTH0_DOMAIN="${ENV_AUTH0_DOMAIN:-${SHELLI_AUTH0_DOMAIN:-dev-fwnv1luqf2t1yke0.us.auth0.com}}"
    SHELLI_AUTH0_CLIENT_ID="${ENV_AUTH0_CLIENT_ID:-${SHELLI_AUTH0_CLIENT_ID:-ziknYEMEkMTaCjkV8M6qTe05htGqds1K}}"
    SHELLI_AUDIENCE="${ENV_AUDIENCE:-${SHELLI_AUDIENCE:-https://api.shelli.local}}"
}

require_deps() {
    command -v curl >/dev/null || die "curl is required"
    command -v jq   >/dev/null || die "jq is required (brew install jq)"
}

# ── auth ──────────────────────────────────────────────────────────────────────

# Decodes a JWT payload to stdout. Adds base64url padding by hand.
jwt_payload() {
    local payload="${1#*.}"; payload="${payload%%.*}"
    payload="${payload//-/+}"; payload="${payload//_//}"
    case $(( ${#payload} % 4 )) in
        2) payload="$payload==" ;;
        3) payload="$payload=" ;;
    esac
    printf '%s' "$payload" | base64 -d 2>/dev/null
}

token_expired() {
    local exp now
    exp=$(jwt_payload "$1" | jq -r '.exp // empty' 2>/dev/null)
    [ -n "$exp" ] || return 0                 # unreadable → treat as expired
    now=$(date +%s)
    [ "$now" -ge "$(( exp - 60 ))" ]          # 60s of slack
}

do_login() {
    require_deps
    local resp
    info "Requesting device code from $SHELLI_AUTH0_DOMAIN..."
    resp=$(curl -sS -X POST "https://$SHELLI_AUTH0_DOMAIN/oauth/device/code" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$SHELLI_AUTH0_CLIENT_ID" \
        -d "audience=$SHELLI_AUDIENCE" \
        -d "scope=openid email profile") || die "could not reach Auth0"

    if jq -e '.error' >/dev/null 2>&1 <<<"$resp"; then
        die "Auth0 rejected the device-code request: $(jq -r '.error_description // .error' <<<"$resp")"
    fi

    local device_code user_code verify_uri interval
    device_code=$(jq -r .device_code           <<<"$resp")
    user_code=$(jq -r .user_code               <<<"$resp")
    verify_uri=$(jq -r .verification_uri_complete <<<"$resp")
    interval=$(jq -r '.interval // 5'          <<<"$resp")

    printf '\n  Open: %s%s%s\n  Code: %s%s%s\n\n' \
        "$CYAN" "$verify_uri" "$RESET" "$BOLD" "$user_code" "$RESET" >&2
    command -v open >/dev/null && open "$verify_uri" >/dev/null 2>&1

    printf 'Waiting for authorization' >&2
    local poll err token
    while true; do
        sleep "$interval"
        poll=$(curl -sS -X POST "https://$SHELLI_AUTH0_DOMAIN/oauth/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=$device_code" \
            -d "client_id=$SHELLI_AUTH0_CLIENT_ID" 2>/dev/null)

        err=$(jq -r '.error // empty' <<<"$poll" 2>/dev/null)
        if [ -z "$err" ]; then
            token=$(jq -r '.access_token // empty' <<<"$poll")
            [ -n "$token" ] || die "Auth0 returned no access token"
            mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
            printf '%s' "$token" > "$TOKEN_FILE" && chmod 600 "$TOKEN_FILE"
            printf '\n%s✓%s signed in — token cached in %s\n' "$GREEN" "$RESET" "$TOKEN_FILE" >&2
            return 0
        fi
        case "$err" in
            authorization_pending|slow_down) printf '.' >&2 ;;
            expired_token) printf '\n' >&2; die "device code expired — run 'shelli login' again" ;;
            access_denied) printf '\n' >&2; die "authorization denied" ;;
            *) printf '\n' >&2; die "$(jq -r '.error_description // .error' <<<"$poll")" ;;
        esac
    done
}

# Echoes a usable token, logging in if the cache is missing or stale.
get_token() {
    local token=""
    [ -f "$TOKEN_FILE" ] && token=$(cat "$TOKEN_FILE")

    if [ -z "$token" ]; then
        info "No cached token — signing in."
        do_login || return 1
        token=$(cat "$TOKEN_FILE")
    elif token_expired "$token"; then
        info "Cached token expired — signing in again."
        do_login || return 1
        token=$(cat "$TOKEN_FILE")
    fi
    printf '%s' "$token"
}

do_logout() {
    if [ -f "$TOKEN_FILE" ]; then
        rm -f "$TOKEN_FILE"
        printf '%s✓%s signed out\n' "$GREEN" "$RESET"
    else
        info "No cached token."
    fi
}

# ── client-side safety net ────────────────────────────────────────────────────

# Mirrors ResponseValidator / Constants.BLOCKED_PATTERNS on the server. Kept
# deliberately separate: the proxy can be out of date or bypassed, and the
# command we are about to run is the one that matters.
BLOCKED_PATTERNS=(
    '(^|[^[:alnum:]_.-])(rm|rmdir|del|mkfs|dd|shred|fdisk|format)([^[:alnum:]_.-]|$)'
    'mkfs\.'
    'kill[[:space:]]+-9'
    '(^|[^[:alnum:]_-])(shutdown|reboot|halt|poweroff)([^[:alnum:]_-]|$)'
    'chmod[[:space:]]+-?[a-zA-Z]*[[:space:]]*777'
    '>[[:space:]]*/dev/'
    ':[[:space:]]*\(\)[[:space:]]*\{'
    '(^|[^[:alnum:]_-])(mv|cp)[[:space:]].*[[:space:]]/dev/null'
)

# Returns 0 (true) and prints the offending pattern if the command is blocked.
blocked_by_client() {
    local cmd="$1" pattern
    for pattern in "${BLOCKED_PATTERNS[@]}"; do
        if grep -Eqi -- "$pattern" <<<"$cmd"; then
            printf '%s' "$pattern"
            return 0
        fi
    done
    return 1
}

# ── gateway calls ─────────────────────────────────────────────────────────────

# Sets HTTP_STATUS and HTTP_BODY. Args: method, path, [json body]
call_gateway() {
    local method="$1" path="$2" body="${3:-}" token raw
    token=$(get_token) || return 1
    [ -n "$token" ] || return 1

    if [ -n "$body" ]; then
        raw=$(curl -sS -X "$method" "$SHELLI_API_URL$path" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -w '\n%{http_code}' -d "$body" 2>&1)
    else
        raw=$(curl -sS -X "$method" "$SHELLI_API_URL$path" \
            -H "Authorization: Bearer $token" \
            -w '\n%{http_code}' 2>&1)
    fi
    if [ $? -ne 0 ]; then
        die "cannot reach the gateway at $SHELLI_API_URL — is it running? ($raw)"
    fi

    HTTP_STATUS="${raw##*$'\n'}"
    HTTP_BODY="${raw%$'\n'*}"
    return 0
}

explain_http_error() {
    case "$HTTP_STATUS" in
        401) die "gateway rejected the token — run 'shelli login'" ;;
        403) die "your account is not on the gateway's allow-list (shelli.allowed-emails)" ;;
        400) die "gateway rejected the request: $HTTP_BODY" ;;
        5*)  die "gateway error ($HTTP_STATUS): $HTTP_BODY" ;;
        *)   die "unexpected response ($HTTP_STATUS): $HTTP_BODY" ;;
    esac
}

do_whoami() {
    require_deps
    call_gateway GET /api/me || exit 1
    [ "$HTTP_STATUS" = "200" ] || explain_http_error
    jq . <<<"$HTTP_BODY"
}

# ── main flow ─────────────────────────────────────────────────────────────────

detect_platform() {
    case "$(uname -s)" in
        Darwin) printf 'macOS %s' "$(sw_vers -productVersion 2>/dev/null)" ;;
        Linux)  printf 'Linux' ;;
        *)      uname -s ;;
    esac
}

detect_shell() {
    # The invoking shell, not this script's bash.
    basename "${SHELL:-unknown}"
}

generate_and_run() {
    local prompt="$1" mode="$2" assume_yes="$3"
    require_deps

    local body
    body=$(jq -nc \
        --arg prompt "$prompt" \
        --arg platform "$(detect_platform)" \
        --arg shell "$(detect_shell)" \
        '{prompt: $prompt, platform: $platform, shell: $shell}')

    info "Thinking..."
    call_gateway POST /api/shell/generate "$body" || exit 1
    [ "$HTTP_STATUS" = "200" ] || explain_http_error

    local command explanation is_safe
    command=$(jq -r '.command // ""'     <<<"$HTTP_BODY")
    explanation=$(jq -r '.explanation // ""' <<<"$HTTP_BODY")
    is_safe=$(jq -r '.isSafe // false'   <<<"$HTTP_BODY")

    if [ -z "$command" ]; then
        printf '%s%s%s\n' "$YELLOW" "${explanation:-The gateway returned no command.}" "$RESET"
        exit 1
    fi

    printf '\n  %s%s%s\n' "$BOLD" "$command" "$RESET"
    [ -n "$explanation" ] && printf '  %s%s%s\n' "$DIM" "$explanation" "$RESET"

    local hit
    hit=$(blocked_by_client "$command")
    local client_blocked=$?

    if [ $client_blocked -eq 0 ]; then
        printf '\n%s✗ blocked locally%s — matches %s\n' "$RED" "$RESET" "$hit" >&2
        printf '  Not running it. Copy it yourself if you really mean to.\n' >&2
        exit 3
    fi
    if [ "$is_safe" != "true" ]; then
        printf '\n%s! the gateway flagged this as unsafe%s\n' "$YELLOW" "$RESET" >&2
    fi

    if [ "$mode" = "display" ]; then
        printf '\n'
        exit 0
    fi

    if [ "$assume_yes" = "true" ]; then
        if [ "$is_safe" != "true" ]; then
            printf '  --yes refused: command is flagged unsafe. Re-run without --yes.\n' >&2
            exit 3
        fi
    else
        [ -t 0 ] || { printf '\n'; exit 0; }   # piped: behave like display mode
        local answer
        printf '\n  Run it? [y/N] ' >&2
        read -r answer </dev/tty
        case "$answer" in
            y|Y|yes|YES) ;;
            *) info "Not running."; exit 0 ;;
        esac
    fi

    printf '\n'
    eval "$command"
    exit $?
}

# ── argument parsing ──────────────────────────────────────────────────────────

load_config

mode="$SHELLI_MODE"
assume_yes="false"
words=()

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help|help)    usage; exit 0 ;;
        -v|--version)      printf 'shelli %s\n' "$VERSION"; exit 0 ;;
        -d|--display)      mode="display"; shift ;;
        -i|--interactive)  mode="interactive"; shift ;;
        -y|--yes)          assume_yes="true"; shift ;;
        login)             do_login; exit 0 ;;
        logout)            do_logout; exit 0 ;;
        whoami)            do_whoami; exit 0 ;;
        config)
            printf 'SHELLI_API_URL=%s\nSHELLI_MODE=%s\nconfig_file=%s%s\ntoken=%s\n' \
                "$SHELLI_API_URL" "$mode" "$CONFIG_FILE" \
                "$([ -f "$CONFIG_FILE" ] || printf ' (absent)')" \
                "$([ -f "$TOKEN_FILE" ] && printf 'cached' || printf 'none')"
            exit 0 ;;
        --)                shift; words+=("$@"); break ;;
        *)                 words+=("$1"); shift ;;
    esac
done

case "$mode" in
    interactive|display) ;;
    *) die "SHELLI_MODE must be 'interactive' or 'display' (got '$mode')" ;;
esac

if [ ${#words[@]} -eq 0 ]; then
    usage
    exit 1
fi

generate_and_run "${words[*]}" "$mode" "$assume_yes"
