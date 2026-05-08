#!/bin/bash

# Dotfiles backup/restore utility.
# Exports a curated set of development environment dotfiles from $HOME
# into a target directory and imports them back. Existing files are
# backed up with a timestamp suffix before being overwritten on import.
# Only regular files are copied; symlinks and directories are skipped.

set -u

# Curated list of dotfiles managed by this script. Add or remove entries
# here to change what gets backed up/restored.
DOTFILES=(
    .zshrc
    .bashrc
    .bash_profile
    .profile
    .gitconfig
    .gitignore_global
    .vimrc
    .tmux.conf
    .editorconfig
    .inputrc
    .npmrc
)

confirm() {
    local prompt="$1"
    read -p "$prompt [y/N]: " ans
    case "$ans" in
        y | Y | yes | Yes | YES) return 0 ;;
        *) return 1 ;;
    esac
}

usage() {
    cat <<EOF
Usage: $0 <command> [arguments]

Commands:
  export <dir>      Back up dotfiles from \$HOME into <dir>
  import <dir>      Restore dotfiles from <dir> into \$HOME
                    (existing files are renamed to <name>.bak.<timestamp>)
  list              Show managed dotfiles and which are present in \$HOME
  help              Show this message

Managed dotfiles:
EOF
    local d
    for d in "${DOTFILES[@]}"; do
        printf "  %s\n" "$d"
    done
}

action_list() {
    printf "%-22s %s\n" "DOTFILE" "STATUS"
    printf "%-22s %s\n" "-------" "------"
    local d path status
    for d in "${DOTFILES[@]}"; do
        path="$HOME/$d"
        if [ -f "$path" ]; then
            status="present"
        elif [ -e "$path" ]; then
            status="present (non-regular, will be skipped)"
        else
            status="missing"
        fi
        printf "%-22s %s\n" "$d" "$status"
    done
}

action_export() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo "Error: missing target directory." >&2
        echo "Usage: $0 export <dir>" >&2
        exit 1
    fi

    if ! mkdir -p "$target"; then
        echo "Error: cannot create target directory '$target'." >&2
        exit 1
    fi

    if [ ! -w "$target" ]; then
        echo "Error: target directory '$target' is not writable." >&2
        exit 1
    fi

    printf "Exporting dotfiles from %s into %s\n" "$HOME" "$target"
    printf -- "----------------------------------------------\n"

    local exported=0 skipped=0 failed=0
    local d src dst
    for d in "${DOTFILES[@]}"; do
        src="$HOME/$d"
        dst="$target/$d"
        if [ ! -e "$src" ]; then
            printf "[skip] %-22s (not found)\n" "$d"
            skipped=$((skipped + 1))
            continue
        fi
        if [ ! -f "$src" ]; then
            printf "[skip] %-22s (not a regular file)\n" "$d"
            skipped=$((skipped + 1))
            continue
        fi
        if cp -p "$src" "$dst"; then
            printf "[ok]   %-22s -> %s\n" "$d" "$dst"
            exported=$((exported + 1))
        else
            printf "[err]  %-22s (copy failed)\n" "$d" >&2
            failed=$((failed + 1))
        fi
    done

    printf -- "----------------------------------------------\n"
    printf "Export complete: %d exported, %d skipped, %d failed.\n" \
        "$exported" "$skipped" "$failed"

    [ "$failed" -eq 0 ]
}

action_import() {
    local source="${1:-}"
    if [ -z "$source" ]; then
        echo "Error: missing source directory." >&2
        echo "Usage: $0 import <dir>" >&2
        exit 1
    fi

    if [ ! -d "$source" ]; then
        echo "Error: '$source' is not a directory." >&2
        exit 1
    fi

    echo "About to import dotfiles from $source into $HOME."
    echo "Existing files will be renamed to <name>.bak.<timestamp>."
    if ! confirm "Proceed?"; then
        echo "Aborted."
        return 0
    fi

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)

    printf -- "----------------------------------------------\n"

    local imported=0 skipped=0 failed=0
    local d src dst
    for d in "${DOTFILES[@]}"; do
        src="$source/$d"
        dst="$HOME/$d"
        if [ ! -e "$src" ]; then
            printf "[skip] %-22s (not in backup)\n" "$d"
            skipped=$((skipped + 1))
            continue
        fi
        if [ ! -f "$src" ]; then
            printf "[skip] %-22s (not a regular file)\n" "$d"
            skipped=$((skipped + 1))
            continue
        fi
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            if ! mv "$dst" "$dst.bak.$stamp"; then
                printf "[err]  %-22s (could not back up existing file)\n" "$d" >&2
                failed=$((failed + 1))
                continue
            fi
            printf "[bak]  %-22s -> %s.bak.%s\n" "$d" "$d" "$stamp"
        fi
        if cp -p "$src" "$dst"; then
            printf "[ok]   %-22s <- %s\n" "$d" "$src"
            imported=$((imported + 1))
        else
            printf "[err]  %-22s (copy failed)\n" "$d" >&2
            failed=$((failed + 1))
        fi
    done

    printf -- "----------------------------------------------\n"
    printf "Import complete: %d imported, %d skipped, %d failed.\n" \
        "$imported" "$skipped" "$failed"

    [ "$failed" -eq 0 ]
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

cmd="$1"
shift

case "$cmd" in
    -h | --help | help) usage; exit 0 ;;
    export) action_export "$@" ;;
    import) action_import "$@" ;;
    list) action_list "$@" ;;
    *)
        echo "Error: unknown command '$cmd'." >&2
        echo
        usage
        exit 1
        ;;
esac
