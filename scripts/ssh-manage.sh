#!/bin/bash

# Local SSH key management utility.
# Lists, views, creates and categorizes SSH keys in ~/.ssh while enforcing
# safe filesystem permissions (700 on the directory, 600 on private keys,
# 644 on public keys). All operations are local and never transmit keys.

set -u

SSH_DIR="${SSH_DIR:-$HOME/.ssh}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

confirm() {
    local prompt="$1"
    read -p "$prompt [y/N]: " ans
    case "$ans" in
        y | Y | yes | Yes | YES) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_ssh_dir() {
    if [ ! -d "$SSH_DIR" ]; then
        echo "SSH directory $SSH_DIR does not exist."
        if confirm "Create it now with mode 700?"; then
            mkdir -p "$SSH_DIR"
            chmod 700 "$SSH_DIR"
            echo "Created $SSH_DIR (mode 700)."
        else
            echo "Aborted."
            exit 1
        fi
    fi
}

# Detect a private SSH key by reading the first line of the file.
# Returns 0 if the file looks like an OpenSSH/PEM private key.
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

# Determine an SSH public key's algorithm by reading its first token
# (e.g. "ssh-rsa AAAA... user@host" -> "ssh-rsa").
public_key_algo() {
    local file="$1"
    awk 'NR==1 {print $1; exit}' "$file" 2>/dev/null
}

# Print the file mode in octal in a portable way (Linux + macOS).
file_mode() {
    local file="$1"
    if stat -c '%a' "$file" >/dev/null 2>&1; then
        stat -c '%a' "$file"
    else
        stat -f '%Mp%Lp' "$file" 2>/dev/null | sed 's/^0*//'
    fi
}

# Friendly category label for a public-key algorithm string.
algo_category() {
    case "$1" in
        ssh-rsa) echo "RSA" ;;
        ssh-dss) echo "DSA (legacy, insecure)" ;;
        ssh-ed25519) echo "Ed25519" ;;
        sk-ssh-ed25519@openssh.com) echo "Ed25519 (FIDO/U2F)" ;;
        ecdsa-sha2-nistp256 | ecdsa-sha2-nistp384 | ecdsa-sha2-nistp521) echo "ECDSA" ;;
        sk-ecdsa-sha2-nistp256@openssh.com) echo "ECDSA (FIDO/U2F)" ;;
        "") echo "Unknown" ;;
        *) echo "$1" ;;
    esac
}

# Best-effort category for a private key without a .pub companion: read the
# PEM header. OpenSSH-format keys hide the algorithm in the binary body, so
# the best we can return there is "OpenSSH (unknown algo)".
private_key_category() {
    local file="$1"
    local head
    head=$(head -n 1 "$file" 2>/dev/null || true)
    case "$head" in
        "-----BEGIN RSA PRIVATE KEY-----") echo "RSA" ;;
        "-----BEGIN DSA PRIVATE KEY-----") echo "DSA (legacy, insecure)" ;;
        "-----BEGIN EC PRIVATE KEY-----") echo "ECDSA" ;;
        "-----BEGIN OPENSSH PRIVATE KEY-----") echo "OpenSSH (unknown algo)" ;;
        "-----BEGIN PRIVATE KEY-----" | "-----BEGIN ENCRYPTED PRIVATE KEY-----") echo "PKCS#8" ;;
        *) echo "Unknown" ;;
    esac
}

# Find every private key in $SSH_DIR (recursive one level: top of dir).
# Echoes one path per line.
collect_private_keys() {
    [ -d "$SSH_DIR" ] || return 0
    local f
    for f in "$SSH_DIR"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            known_hosts | known_hosts.old | authorized_keys | config) continue ;;
            *.pub) continue ;;
        esac
        if is_private_key "$f"; then
            echo "$f"
        fi
    done
}

# Find every public key in $SSH_DIR (files ending in .pub).
collect_public_keys() {
    [ -d "$SSH_DIR" ] || return 0
    local f
    for f in "$SSH_DIR"/*.pub; do
        [ -f "$f" ] || continue
        echo "$f"
    done
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

action_list() {
    echo "SSH keys in $SSH_DIR"
    echo "----------------------------------------------"

    local privs pubs
    privs=$(collect_private_keys)
    pubs=$(collect_public_keys)

    if [ -z "$privs" ] && [ -z "$pubs" ]; then
        echo "No SSH keys found."
        return
    fi

    printf "%-30s %-10s %-22s %s\n" "FILE" "MODE" "TYPE" "PAIR"
    printf "%-30s %-10s %-22s %s\n" "----" "----" "----" "----"

    if [ -n "$privs" ]; then
        local p
        while IFS= read -r p; do
            local mode pair_status algo category
            mode=$(file_mode "$p")
            if [ -f "$p.pub" ]; then
                pair_status="pub: $(basename "$p.pub")"
                algo=$(public_key_algo "$p.pub")
                category=$(algo_category "$algo")
            else
                pair_status="(no .pub)"
                category=$(private_key_category "$p")
            fi
            printf "%-30s %-10s %-22s %s\n" \
                "$(basename "$p")" "$mode" "$category" "$pair_status"
        done <<< "$privs"
    fi

    # Orphan public keys (no matching private file).
    if [ -n "$pubs" ]; then
        local pub priv_path
        while IFS= read -r pub; do
            priv_path="${pub%.pub}"
            if [ ! -f "$priv_path" ]; then
                local mode algo category
                mode=$(file_mode "$pub")
                algo=$(public_key_algo "$pub")
                category=$(algo_category "$algo")
                printf "%-30s %-10s %-22s %s\n" \
                    "$(basename "$pub")" "$mode" "$category" "(orphan public)"
            fi
        done <<< "$pubs"
    fi
}

action_categorize() {
    echo "Key categories in $SSH_DIR"
    echo "----------------------------------------------"

    local pubs
    pubs=$(collect_public_keys)
    if [ -z "$pubs" ]; then
        echo "No public keys to categorize."
        return
    fi

    # Build "category|file" lines, then sort and group.
    local pub algo category
    while IFS= read -r pub; do
        algo=$(public_key_algo "$pub")
        category=$(algo_category "$algo")
        printf "%s|%s\n" "$category" "$(basename "$pub")"
    done <<< "$pubs" | sort | awk -F'|' '
        $1 != prev {
            if (prev != "") print ""
            print "[" $1 "]"
            prev = $1
        }
        { print "  - " $2 }
    '
}

action_view_public() {
    local pubs
    pubs=$(collect_public_keys)
    if [ -z "$pubs" ]; then
        echo "No public keys found."
        return
    fi

    echo "Available public keys:"
    local i=1 entries=()
    while IFS= read -r pub; do
        printf "%2d. %s\n" "$i" "$(basename "$pub")"
        entries+=("$pub")
        i=$((i + 1))
    done <<< "$pubs"

    read -p "Enter number to view (or blank to cancel): " choice
    [ -z "$choice" ] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Error: invalid number." >&2
        return
    fi
    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#entries[@]}" ]; then
        echo "Error: out of range." >&2
        return
    fi

    echo "----------------------------------------------"
    cat "${entries[$idx]}"
    echo "----------------------------------------------"
}

action_view_private() {
    local privs
    privs=$(collect_private_keys)
    if [ -z "$privs" ]; then
        echo "No private keys found."
        return
    fi

    echo "Available private keys:"
    local i=1 entries=()
    while IFS= read -r p; do
        local mode
        mode=$(file_mode "$p")
        printf "%2d. %s (mode %s)\n" "$i" "$(basename "$p")" "$mode"
        entries+=("$p")
        i=$((i + 1))
    done <<< "$privs"

    read -p "Enter number to view (or blank to cancel): " choice
    [ -z "$choice" ] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Error: invalid number." >&2
        return
    fi
    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#entries[@]}" ]; then
        echo "Error: out of range." >&2
        return
    fi

    local target="${entries[$idx]}"
    local mode
    mode=$(file_mode "$target")

    echo
    echo "WARNING: you are about to print a PRIVATE KEY to the terminal."
    echo "  Anyone watching the screen, scrollback, or terminal logs will"
    echo "  see it. Make sure you are in a private environment."
    echo "  File: $target  (mode: $mode)"
    if [ "$mode" != "600" ] && [ "$mode" != "400" ]; then
        echo "  NOTE: insecure permissions; expected 600 or 400."
    fi
    if ! confirm "Display the private key now?"; then
        echo "Aborted."
        return
    fi

    echo "----------------------------------------------"
    cat "$target"
    echo "----------------------------------------------"
}

action_create() {
    ensure_ssh_dir

    echo "Create a new SSH key"
    echo "----------------------------------------------"
    echo "Select key type:"
    echo "  1. Ed25519 (recommended)"
    echo "  2. RSA 4096"
    echo "  3. ECDSA (nistp256)"
    read -p "Choice [1]: " ktype
    ktype="${ktype:-1}"

    local algo bits=""
    case "$ktype" in
        1) algo="ed25519" ;;
        2) algo="rsa"; bits="4096" ;;
        3) algo="ecdsa"; bits="256" ;;
        *) echo "Error: invalid key type." >&2; return ;;
    esac

    local default_name="id_${algo}"
    read -p "Key file name [${default_name}]: " keyname
    keyname="${keyname:-$default_name}"
    # Reject path separators to keep the key inside SSH_DIR.
    case "$keyname" in
        */* | "")
            echo "Error: key name must not contain '/'." >&2
            return
            ;;
    esac
    local keypath="$SSH_DIR/$keyname"

    if [ -e "$keypath" ] || [ -e "$keypath.pub" ]; then
        echo "Error: $keypath or $keypath.pub already exists." >&2
        return
    fi

    read -p "Comment (e.g. email or host) [$(whoami)@$(hostname)]: " comment
    comment="${comment:-$(whoami)@$(hostname)}"

    local args=(-t "$algo" -f "$keypath" -C "$comment")
    if [ -n "$bits" ]; then
        args+=(-b "$bits")
    fi

    # ssh-keygen will prompt the user for a passphrase interactively, which
    # is the desired behavior — passphrases must never be passed on the
    # command line.
    if ! ssh-keygen "${args[@]}"; then
        echo "Error: ssh-keygen failed." >&2
        return
    fi

    chmod 700 "$SSH_DIR"
    chmod 600 "$keypath"
    [ -f "$keypath.pub" ] && chmod 644 "$keypath.pub"

    echo "Key created:"
    echo "  private: $keypath (mode 600)"
    [ -f "$keypath.pub" ] && echo "  public:  $keypath.pub (mode 644)"
}

action_fix_permissions() {
    ensure_ssh_dir

    echo "Will normalize permissions in $SSH_DIR:"
    echo "  directory  -> 700"
    echo "  private    -> 600"
    echo "  public/.pub-> 644"
    if ! confirm "Proceed?"; then
        echo "Aborted."
        return
    fi

    chmod 700 "$SSH_DIR"
    echo "[ok] $SSH_DIR -> 700"

    local f
    for f in "$SSH_DIR"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            *.pub)
                chmod 644 "$f"
                echo "[ok] $f -> 644"
                ;;
            known_hosts | known_hosts.old | config | authorized_keys)
                chmod 600 "$f"
                echo "[ok] $f -> 600"
                ;;
            *)
                if is_private_key "$f"; then
                    chmod 600 "$f"
                    echo "[ok] $f -> 600 (private key)"
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

print_menu() {
    echo "SSH key manager  ($SSH_DIR)"
    echo "----------------------------------------------"
    echo "  1. List keys"
    echo "  2. Categorize keys by type"
    echo "  3. View a public key"
    echo "  4. View a private key (with confirmation)"
    echo "  5. Create a new key"
    echo "  6. Fix permissions (700 / 600 / 644)"
    echo "  q. Quit"
    echo "----------------------------------------------"
}

show_help() {
    cat <<EOF
Usage: $0 [help]

Interactive local SSH key manager for $SSH_DIR.

The script prints a menu with the following options:
  1. List keys                 show every private/public key with mode + algorithm
  2. Categorize keys by type   group public keys by algorithm (Ed25519, RSA, ...)
  3. View a public key         print the contents of a chosen .pub file
  4. View a private key        print a private key after an explicit confirmation
  5. Create a new key          run ssh-keygen with safe defaults (Ed25519/RSA/ECDSA)
  6. Fix permissions           normalize $SSH_DIR (700) and key modes (600 / 644)
  q. Quit

Environment:
  SSH_DIR      Override the SSH directory (default: \$HOME/.ssh)

Examples:
  $0
  SSH_DIR=/tmp/ssh $0
  $0 help

For non-interactive key generation/removal, use the dedicated commands
'ssh-keygen' and 'ssh-keyremove'.
EOF
}

case "${1:-}" in
    -h | --help | help)
        show_help
        exit 0
        ;;
esac

print_menu
read -p "Enter your choice: " choice

case "$choice" in
    1) action_list ;;
    2) action_categorize ;;
    3) action_view_public ;;
    4) action_view_private ;;
    5) action_create ;;
    6) action_fix_permissions ;;
    q | Q) echo "Bye."; exit 0 ;;
    *) echo "Error: invalid option." >&2; exit 1 ;;
esac

echo "----------------------------------------------"
echo "Done."
