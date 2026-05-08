#!/usr/bin/env bash

# Safely remove an SSH key pair and clean up the surrounding configuration:
#   * delete the private key file and its companion .pub
#   * strip matching Host blocks from <dir>/config (matched by alias and/or
#     by IdentityFile reference to the key being removed)
#   * drop matching entries from <dir>/known_hosts via ssh-keygen -R
#
# Designed as the non-interactive complement to ssh-keygen.sh: parameters
# are taken from the command line. A confirmation prompt protects the
# irreversible deletions unless --yes is supplied.

set -euo pipefail

DEFAULT_DIR="${SSH_DIR:-$HOME/.ssh}"

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 (--name <name> | --path <path>) [options]

Remove an SSH key pair and clean up the SSH config and known_hosts.

Key selection (one required):
  -n, --name <name>            Key file name inside <dir> (e.g. id_rsa_work).
  -p, --path <path>            Full path to the private key file.

Options:
  -d, --dir <directory>        SSH directory (default: ${DEFAULT_DIR}).
  -H, --host <alias>           Host alias whose entries should also be removed
                               from <dir>/config and <dir>/known_hosts.
                               May be repeated to clean multiple aliases.
      --no-config              Do not modify the SSH config file.
      --no-known-hosts         Do not modify known_hosts.
      --keep-private           Do not delete the private key file.
      --keep-public            Do not delete the .pub file.
  -y, --yes                    Do not prompt for confirmation.
  -h, --help                   Show this help and exit.

Examples:
  $0 --name id_rsa_work
  $0 --name id_ed25519_github --host github.com --yes
  $0 --path /tmp/keys/deploy --no-config
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

name=""
path=""
dir=""
hosts=()
update_config=1
update_known_hosts=1
remove_private=1
remove_public=1
assume_yes=0

require_value() {
    if [ "$2" -lt 2 ]; then
        err "missing value for $1"
        usage >&2
        exit 2
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n | --name)        require_value "$1" $#; name="$2";       shift 2 ;;
        -p | --path)        require_value "$1" $#; path="$2";       shift 2 ;;
        -d | --dir)         require_value "$1" $#; dir="$2";        shift 2 ;;
        -H | --host)        require_value "$1" $#; hosts+=("$2");   shift 2 ;;
        --no-config)        update_config=0; shift ;;
        --no-known-hosts)   update_known_hosts=0; shift ;;
        --keep-private)     remove_private=0; shift ;;
        --keep-public)      remove_public=0; shift ;;
        -y | --yes)         assume_yes=1; shift ;;
        -h | --help)        usage; exit 0 ;;
        --)                 shift; break ;;
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

dir="${dir:-$DEFAULT_DIR}"

if [ -n "$name" ] && [ -n "$path" ]; then
    err "use either --name or --path, not both"
    exit 2
fi

if [ -z "$name" ] && [ -z "$path" ]; then
    err "one of --name or --path is required"
    usage >&2
    exit 2
fi

if [ -n "$name" ]; then
    case "$name" in
        */* | "" | "." | "..")
            err "key name must not be empty, '.', '..', or contain '/'"
            exit 2
            ;;
    esac
    keypath="$dir/$name"
else
    keypath="$path"
fi

pubpath="${keypath}.pub"

# ---------------------------------------------------------------------------
# Plan + confirmation
# ---------------------------------------------------------------------------

log "About to remove SSH key pair:"
if [ "$remove_private" -eq 1 ]; then
    log "  private:     $keypath"
else
    log "  private:     $keypath (kept, --keep-private)"
fi
if [ "$remove_public" -eq 1 ]; then
    log "  public:      $pubpath"
else
    log "  public:      $pubpath (kept, --keep-public)"
fi
if [ "$update_config" -eq 1 ]; then
    log "  ssh config:  $dir/config (Host blocks referencing this key${hosts[*]:+ or aliases: ${hosts[*]}})"
fi
if [ "$update_known_hosts" -eq 1 ]; then
    if [ "${#hosts[@]}" -gt 0 ]; then
        log "  known_hosts: $dir/known_hosts (entries for: ${hosts[*]})"
    else
        log "  known_hosts: not touched (no --host provided)"
    fi
fi

if [ "$assume_yes" -ne 1 ]; then
    read -r -p "Proceed? [y/N]: " ans
    case "$ans" in
        y | Y | yes | Yes | YES) ;;
        *) log "Aborted."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------------------
# Delete key files
# ---------------------------------------------------------------------------

if [ "$remove_private" -eq 1 ]; then
    if [ -f "$keypath" ]; then
        rm -f -- "$keypath"
        log "[ok]   removed $keypath"
    elif [ -e "$keypath" ]; then
        warn "$keypath exists but is not a regular file; not removing"
    else
        log "[skip] $keypath does not exist"
    fi
fi

if [ "$remove_public" -eq 1 ]; then
    if [ -f "$pubpath" ]; then
        rm -f -- "$pubpath"
        log "[ok]   removed $pubpath"
    elif [ -e "$pubpath" ]; then
        warn "$pubpath exists but is not a regular file; not removing"
    else
        log "[skip] $pubpath does not exist"
    fi
fi

# ---------------------------------------------------------------------------
# Clean SSH config: drop Host blocks that target this key by IdentityFile
# or whose alias list contains a requested --host value.
# ---------------------------------------------------------------------------

if [ "$update_config" -eq 1 ]; then
    config_path="$dir/config"
    if [ ! -f "$config_path" ]; then
        log "[skip] $config_path does not exist"
    else
        # Build the list of IdentityFile values to match. Always include the
        # literal keypath; if it sits inside $HOME, also accept the ~ form
        # since ssh config files commonly use that.
        candidate_paths=("$keypath")
        if [ -n "${HOME:-}" ] && [ "${keypath#"$HOME"/}" != "$keypath" ]; then
            candidate_paths+=("~/${keypath#"$HOME"/}")
        fi

        # Pass aliases / paths to awk as US-separated strings (\037 is
        # never a legal character in either ssh aliases or filesystem
        # paths in practice).
        aliases_str=""
        if [ "${#hosts[@]}" -gt 0 ]; then
            aliases_str="$(printf '%s\037' "${hosts[@]}")"
        fi
        paths_str="$(printf '%s\037' "${candidate_paths[@]}")"

        tmp_cfg="$(mktemp "${config_path}.XXXXXX")"
        # awk reads the config as a stream of "Host" blocks. Lines before
        # the first Host directive are passed through unchanged. For each
        # Host block, we buffer all lines and decide at the next Host (or
        # at EOF) whether to keep it. A block is dropped if either:
        #   * its Host line lists one of the requested aliases, or
        #   * it contains an "IdentityFile" pointing at the deleted key.
        awk -v aliases="$aliases_str" -v paths="$paths_str" '
            BEGIN {
                naliases = split(aliases, A, "\037")
                npaths   = split(paths,   P, "\037")
                in_block = 0
                keep_block = 1
                n = 0
            }
            function flush_block() {
                if (keep_block) {
                    for (i = 0; i < n; i++) print buf[i]
                }
                n = 0
                keep_block = 1
            }
            {
                first = $1
                lower_first = tolower(first)

                if (lower_first == "host") {
                    flush_block()
                    in_block = 1
                    keep_block = 1
                    for (i = 2; i <= NF; i++) {
                        for (j = 1; j <= naliases; j++) {
                            if (A[j] != "" && $i == A[j]) keep_block = 0
                        }
                    }
                    buf[n++] = $0
                    next
                }

                if (in_block) {
                    if (lower_first == "identityfile" && NF >= 2) {
                        val = $2
                        # strip surrounding quotes if any
                        if (substr(val, 1, 1) == "\"" && substr(val, length(val), 1) == "\"") {
                            val = substr(val, 2, length(val) - 2)
                        }
                        for (j = 1; j <= npaths; j++) {
                            if (P[j] != "" && val == P[j]) keep_block = 0
                        }
                    }
                    buf[n++] = $0
                } else {
                    print
                }
            }
            END { flush_block() }
        ' "$config_path" > "$tmp_cfg"

        if cmp -s "$config_path" "$tmp_cfg"; then
            log "[skip] $config_path: no matching Host blocks"
            rm -f -- "$tmp_cfg"
        else
            # Preserve the file mode (or fall back to 600).
            chmod --reference="$config_path" "$tmp_cfg" 2>/dev/null || chmod 600 "$tmp_cfg"
            mv -- "$tmp_cfg" "$config_path"
            log "[ok]   cleaned matching Host blocks in $config_path"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Clean known_hosts: ssh-keygen -R is the canonical, hashed-entry-aware way.
# ---------------------------------------------------------------------------

if [ "$update_known_hosts" -eq 1 ]; then
    if [ "${#hosts[@]}" -eq 0 ]; then
        log "[skip] known_hosts: no --host provided"
    else
        kh="$dir/known_hosts"
        if [ ! -f "$kh" ]; then
            log "[skip] $kh does not exist"
        elif ! command -v ssh-keygen >/dev/null 2>&1; then
            warn "ssh-keygen not found in PATH; cannot clean known_hosts"
        else
            for h in "${hosts[@]}"; do
                if ssh-keygen -R "$h" -f "$kh" >/dev/null 2>&1; then
                    log "[ok]   removed $h from $kh"
                else
                    warn "failed to remove $h from $kh"
                fi
            done
        fi
    fi
fi

log
log "Done."
