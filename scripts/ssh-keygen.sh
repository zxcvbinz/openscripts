#!/usr/bin/env bash

# Generate a new SSH key pair (Ed25519 or RSA) from CLI options and,
# when a host alias is supplied, append a matching block to the SSH
# config so the new key is picked up automatically for that host.
#
# Designed to be non-interactive (aside from the passphrase prompt that
# ssh-keygen itself raises): all parameters are provided on the command
# line so the script can be used in scripts and CI as well as by humans.

set -euo pipefail

DEFAULT_DIR="${SSH_DIR:-$HOME/.ssh}"
DEFAULT_TYPE="ed25519"
DEFAULT_RSA_BITS=4096
DEFAULT_USER="git"

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 --email <email> [options]

Generate a new SSH key pair and (optionally) update the SSH config.

Required:
  -e, --email <email>          Email used as the key comment.

Options:
  -t, --type <ed25519|rsa>     Key algorithm (default: ${DEFAULT_TYPE}).
  -n, --name <name>            Key file name (default: id_<type>).
  -d, --dir <directory>        Output directory (default: ${DEFAULT_DIR}).
  -b, --bits <bits>            RSA key size (default: ${DEFAULT_RSA_BITS}).
                               Ignored for ed25519.
  -H, --host <alias>           Host alias to register in <dir>/config.
                               When provided, a Host block pointing at the
                               new key is appended to the SSH config.
      --hostname <hostname>    HostName for the Host block (default: alias).
  -u, --user <user>            User for the Host block (default: ${DEFAULT_USER}).
      --no-config              Do not update the SSH config file.
  -h, --help                   Show this help and exit.

Notes:
  * ssh-keygen will prompt interactively for a passphrase. Using a strong
    passphrase is strongly recommended.
  * Existing key files are never overwritten; the script aborts instead.

Examples:
  $0 --email me@example.com
  $0 -e me@example.com -t rsa -b 4096 -n id_rsa_work
  $0 -e me@example.com -H github.com --user git
  $0 -e me@example.com -d /tmp/keys -n deploy --no-config
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

type_arg=""
email=""
name=""
dir=""
bits=""
host_alias=""
hostname=""
ssh_user=""
update_config=1

require_value() {
    if [ "$2" -lt 2 ]; then
        err "missing value for $1"
        usage >&2
        exit 2
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        -t | --type)     require_value "$1" $#; type_arg="$2";   shift 2 ;;
        -e | --email)    require_value "$1" $#; email="$2";      shift 2 ;;
        -n | --name)     require_value "$1" $#; name="$2";       shift 2 ;;
        -d | --dir)      require_value "$1" $#; dir="$2";        shift 2 ;;
        -b | --bits)     require_value "$1" $#; bits="$2";       shift 2 ;;
        -H | --host)     require_value "$1" $#; host_alias="$2"; shift 2 ;;
        --hostname)      require_value "$1" $#; hostname="$2";   shift 2 ;;
        -u | --user)     require_value "$1" $#; ssh_user="$2";   shift 2 ;;
        --no-config)     update_config=0; shift ;;
        -h | --help)     usage; exit 0 ;;
        --)              shift; break ;;
        -*)
            err "unknown option: $1"
            usage >&2
            exit 2
            ;;
        *)
            err "unexpected positional argument: $1"
            usage >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation and defaults
# ---------------------------------------------------------------------------

if [ -z "$email" ]; then
    err "--email is required"
    usage >&2
    exit 2
fi

case "$email" in
    *@*.*) : ;;
    *)
        err "--email value '$email' does not look like a valid email"
        exit 2
        ;;
esac

key_type="${type_arg:-$DEFAULT_TYPE}"
case "$key_type" in
    ed25519 | ED25519)
        key_type="ed25519"
        if [ -n "$bits" ]; then
            warn "--bits is ignored for ed25519 keys"
            bits=""
        fi
        ;;
    rsa | RSA)
        key_type="rsa"
        bits="${bits:-$DEFAULT_RSA_BITS}"
        case "$bits" in
            '' | *[!0-9]*)
                err "--bits must be a positive integer (got '$bits')"
                exit 2
                ;;
        esac
        if [ "$bits" -lt 2048 ]; then
            err "RSA --bits must be >= 2048 (got $bits)"
            exit 2
        fi
        ;;
    *)
        err "unsupported key type: '$key_type' (use ed25519 or rsa)"
        exit 2
        ;;
esac

dir="${dir:-$DEFAULT_DIR}"
name="${name:-id_${key_type}}"

case "$name" in
    */* | "" | "." | "..")
        err "key name must not be empty, '.', '..', or contain '/'"
        exit 2
        ;;
esac

# ---------------------------------------------------------------------------
# Generate the key
# ---------------------------------------------------------------------------

if ! command -v ssh-keygen >/dev/null 2>&1; then
    err "ssh-keygen not found in PATH"
    exit 1
fi

if [ ! -d "$dir" ]; then
    log "Creating directory $dir (mode 700)..."
    mkdir -p "$dir"
fi
chmod 700 "$dir"

keypath="$dir/$name"
if [ -e "$keypath" ] || [ -e "$keypath.pub" ]; then
    err "$keypath or $keypath.pub already exists; refusing to overwrite"
    exit 1
fi

args=(-t "$key_type" -f "$keypath" -C "$email")
if [ "$key_type" = "rsa" ]; then
    args+=(-b "$bits")
fi

log "Generating $key_type key at $keypath"
log "Comment: $email"
log

if ! ssh-keygen "${args[@]}"; then
    err "ssh-keygen failed"
    exit 1
fi

chmod 600 "$keypath"
if [ -f "$keypath.pub" ]; then
    chmod 644 "$keypath.pub"
fi

log
log "Key created:"
log "  private: $keypath (mode 600)"
if [ -f "$keypath.pub" ]; then
    log "  public:  $keypath.pub (mode 644)"
fi

# ---------------------------------------------------------------------------
# SSH config update
# ---------------------------------------------------------------------------

if [ "$update_config" -eq 0 ]; then
    log
    log "SSH config not updated (--no-config)."
    exit 0
fi

if [ -z "$host_alias" ]; then
    log
    log "No --host provided; SSH config not updated."
    log "To use this key for a specific host, add a block like:"
    log
    log "  Host <alias>"
    log "      HostName <hostname>"
    log "      User <user>"
    log "      IdentityFile $keypath"
    log "      IdentitiesOnly yes"
    exit 0
fi

config_path="$dir/config"
hostname="${hostname:-$host_alias}"
ssh_user="${ssh_user:-$DEFAULT_USER}"

# Refuse to add a duplicate Host alias. awk inspects every "Host ..." line
# and matches each whitespace-separated alias on it.
if [ -f "$config_path" ] && awk -v alias="$host_alias" '
        /^[[:space:]]*Host[[:space:]]+/ {
            for (i = 2; i <= NF; i++) {
                if ($i == alias) { found = 1; exit }
            }
        }
        END { exit !found }
    ' "$config_path"; then
    warn "Host '$host_alias' already exists in $config_path; not modifying."
    log "Update that block manually to point IdentityFile at $keypath."
    exit 0
fi

{
    if [ -s "$config_path" ]; then
        printf '\n'
    fi
    printf 'Host %s\n' "$host_alias"
    printf '    HostName %s\n' "$hostname"
    printf '    User %s\n' "$ssh_user"
    printf '    IdentityFile %s\n' "$keypath"
    printf '    IdentitiesOnly yes\n'
} >> "$config_path"

chmod 600 "$config_path"

log
log "Updated $config_path with Host block:"
log "  Host         $host_alias"
log "  HostName     $hostname"
log "  User         $ssh_user"
log "  IdentityFile $keypath"
