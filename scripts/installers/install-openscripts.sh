#!/bin/bash
#
# install-openscripts: create or remove a symlink to openscripts.sh in
# /usr/local/bin so the dispatcher is callable as `openscripts` from anywhere.
# The uninstaller refuses to remove anything that is not a symlink to this
# project's openscripts.sh, to avoid touching unrelated files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$PROJECT_ROOT/openscripts.sh"
TARGET_DIR="/usr/local/bin"
LINK_NAME="openscripts"
TARGET="$TARGET_DIR/$LINK_NAME"

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  install     Symlink openscripts.sh to $TARGET
  uninstall   Remove $TARGET (only if it points to this project)
  status      Show whether openscripts is currently installed

Run with sudo if you do not have write access to $TARGET_DIR.
EOF
}

err() {
    printf 'Error: %s\n' "$1" >&2
}

info() {
    printf '%s\n' "$1"
}

require_source() {
    if [ ! -f "$SOURCE" ]; then
        err "openscripts.sh not found at $SOURCE"
        exit 1
    fi
    if [ ! -x "$SOURCE" ]; then
        err "openscripts.sh is not executable. Run: chmod +x $SOURCE"
        exit 1
    fi
}

run_with_privilege() {
    if [ -w "$TARGET_DIR" ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        err "$TARGET_DIR is not writable and sudo is not available."
        exit 1
    fi
}

action_install() {
    require_source

    if [ ! -d "$TARGET_DIR" ]; then
        err "$TARGET_DIR does not exist."
        exit 1
    fi

    if [ -L "$TARGET" ]; then
        local current
        current="$(readlink "$TARGET")"
        if [ "$current" = "$SOURCE" ]; then
            info "openscripts is already installed at $TARGET."
            return 0
        fi
        err "$TARGET already exists as a symlink to $current."
        err "Remove it manually or run '$0 uninstall' if it points to a previous install."
        exit 1
    fi

    if [ -e "$TARGET" ]; then
        err "$TARGET already exists and is not a symlink. Refusing to overwrite."
        exit 1
    fi

    run_with_privilege ln -s "$SOURCE" "$TARGET"
    info "openscripts installed at $TARGET -> $SOURCE"
}

action_uninstall() {
    if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        info "Nothing to do: $TARGET does not exist."
        return 0
    fi

    if [ ! -L "$TARGET" ]; then
        err "$TARGET exists but is not a symlink. Refusing to remove."
        exit 1
    fi

    local current
    current="$(readlink "$TARGET")"
    if [ "$current" != "$SOURCE" ]; then
        err "$TARGET points to $current, not to $SOURCE. Refusing to remove."
        exit 1
    fi

    run_with_privilege rm -f "$TARGET"
    info "openscripts removed from $TARGET."
}

action_status() {
    if [ -L "$TARGET" ]; then
        local current
        current="$(readlink "$TARGET")"
        if [ "$current" = "$SOURCE" ]; then
            info "Installed: $TARGET -> $current"
        else
            info "Foreign symlink: $TARGET -> $current (not from this project)"
        fi
        return 0
    fi
    if [ -e "$TARGET" ]; then
        info "Conflict: $TARGET exists but is not a symlink."
        return 0
    fi
    info "Not installed."
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    install)            action_install ;;
    uninstall)          action_uninstall ;;
    status)             action_status ;;
    -h | --help | help) usage ;;
    *)
        err "unknown command '$1'"
        usage
        exit 1
        ;;
esac
