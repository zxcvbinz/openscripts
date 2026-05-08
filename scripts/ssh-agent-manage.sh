#!/usr/bin/env bash

# Interactively select a private SSH key from ~/.ssh, ensure ssh-agent is
# running and load the chosen key into the agent with ssh-add.
#
# ssh-agent normally exports SSH_AUTH_SOCK / SSH_AGENT_PID into the calling
# shell. Because this script runs in a subprocess, those variables would be
# lost when it exits. To work around that we persist the agent environment
# in <SSH_DIR>/agent.env so the user (and future invocations) can reuse the
# same agent by sourcing that file.

set -uo pipefail

SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
AGENT_ENV_FILE="${AGENT_ENV_FILE:-$SSH_DIR/agent.env}"

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 [options]

Select a private SSH key, start ssh-agent if needed, and load the key with
ssh-add. The agent environment is saved to ${AGENT_ENV_FILE} so it can be
reused across shells via:

    . ${AGENT_ENV_FILE}

Options:
  -k, --key <path>    Skip selection and load the key at <path> directly.
  -l, --list          List private keys and exit (no selection, no load).
  -h, --help          Show this help and exit.
EOF
}

# Detect a private SSH key by reading the first line of the file.
is_private_key() {
    local file="$1"
    [ -f "$file" ] || return 1
    [ -r "$file" ] || return 1
    local head
    head=$(head -n 1 "$file" 2>/dev/null || true)
    case "$head" in
        "-----BEGIN OPENSSH PRIVATE KEY-----") return 0 ;;
        "-----BEGIN RSA PRIVATE KEY-----") return 0 ;;
        "-----BEGIN DSA PRIVATE KEY-----") return 0 ;;
        "-----BEGIN EC PRIVATE KEY-----") return 0 ;;
        "-----BEGIN PRIVATE KEY-----") return 0 ;;
        "-----BEGIN ENCRYPTED PRIVATE KEY-----") return 0 ;;
    esac
    return 1
}

collect_private_keys() {
    [ -d "$SSH_DIR" ] || return 0
    local f
    for f in "$SSH_DIR"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            known_hosts | known_hosts.old | authorized_keys | config) continue ;;
            *.pub) continue ;;
            agent.env) continue ;;
        esac
        if is_private_key "$f"; then
            echo "$f"
        fi
    done
}

# Returns 0 when an ssh-agent reachable via $SSH_AUTH_SOCK responds. ssh-add
# exits 0 when the agent has identities, 1 when it has none, 2 when it cannot
# reach the agent at all -- only the last case means "no usable agent".
agent_is_reachable() {
    [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
    ssh-add -l >/dev/null 2>&1
    local rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]
}

load_agent_env() {
    [ -f "$AGENT_ENV_FILE" ] || return 1
    # shellcheck disable=SC1090
    . "$AGENT_ENV_FILE" >/dev/null 2>&1
}

start_agent() {
    if ! command -v ssh-agent >/dev/null 2>&1; then
        err "ssh-agent not found in PATH"
        return 1
    fi

    log "Starting a new ssh-agent..."
    local agent_output
    if ! agent_output=$(ssh-agent -s); then
        err "failed to start ssh-agent"
        return 1
    fi

    # ssh-agent -s prints sh-compatible "VAR=value; export VAR;" lines plus a
    # final "echo Agent pid ..." that we strip out so the file is pure env.
    printf '%s\n' "$agent_output" \
        | grep -E '^(SSH_AUTH_SOCK|SSH_AGENT_PID)=' > "$AGENT_ENV_FILE"
    chmod 600 "$AGENT_ENV_FILE"

    # shellcheck disable=SC1090
    . "$AGENT_ENV_FILE"
    log "Agent started (pid ${SSH_AGENT_PID:-?}). Environment saved to:"
    log "  $AGENT_ENV_FILE"
}

ensure_agent() {
    if agent_is_reachable; then
        return 0
    fi
    if load_agent_env && agent_is_reachable; then
        log "Reusing existing ssh-agent from $AGENT_ENV_FILE."
        return 0
    fi
    start_agent
}

select_key_interactive() {
    local privs
    privs=$(collect_private_keys)
    if [ -z "$privs" ]; then
        err "no private keys found in $SSH_DIR"
        return 1
    fi

    log "Available private keys in $SSH_DIR:" >&2
    local i=1 entries=()
    while IFS= read -r p; do
        printf '%2d. %s\n' "$i" "$(basename "$p")" >&2
        entries+=("$p")
        i=$((i + 1))
    done <<< "$privs"

    local choice
    read -r -p "Enter number (or blank to cancel): " choice
    if [ -z "$choice" ]; then
        log "Aborted." >&2
        return 1
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        err "invalid number: '$choice'"
        return 1
    fi
    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#entries[@]}" ]; then
        err "out of range"
        return 1
    fi

    printf '%s\n' "${entries[$idx]}"
}

action_list() {
    local privs
    privs=$(collect_private_keys)
    if [ -z "$privs" ]; then
        log "No private keys found in $SSH_DIR."
        return 0
    fi
    log "Private keys in $SSH_DIR:"
    local p
    while IFS= read -r p; do
        printf '  - %s\n' "$(basename "$p")"
    done <<< "$privs"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

key_arg=""
list_only=0

while [ $# -gt 0 ]; do
    case "$1" in
        -k | --key)
            if [ "$#" -lt 2 ]; then
                err "missing value for $1"
                usage >&2
                exit 2
            fi
            key_arg="$2"
            shift 2
            ;;
        -l | --list)  list_only=1; shift ;;
        -h | --help)  usage; exit 0 ;;
        --)           shift; break ;;
        -*)
            err "unknown option: $1"
            usage >&2
            exit 2
            ;;
        *)
            err "unexpected argument: $1"
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$list_only" -eq 1 ]; then
    action_list
    exit 0
fi

if ! command -v ssh-add >/dev/null 2>&1; then
    err "ssh-add not found in PATH"
    exit 1
fi

# Resolve the target key.
if [ -n "$key_arg" ]; then
    key_path="$key_arg"
    if [ ! -f "$key_path" ]; then
        err "key file not found: $key_path"
        exit 1
    fi
    if ! is_private_key "$key_path"; then
        err "$key_path does not look like a private key"
        exit 1
    fi
else
    if [ ! -d "$SSH_DIR" ]; then
        err "SSH directory $SSH_DIR does not exist"
        exit 1
    fi
    key_path=$(select_key_interactive) || exit 1
fi

ensure_agent || exit 1

log "Loading key into agent: $key_path"
# ssh-add will prompt interactively for the passphrase if the key has one.
if ! ssh-add "$key_path"; then
    err "ssh-add failed"
    exit 1
fi

log
log "Key loaded. Identities currently in the agent:"
ssh-add -l || true
log
log "To reuse this agent in another shell, run:"
log "  . $AGENT_ENV_FILE"
