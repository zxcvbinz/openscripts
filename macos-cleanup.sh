#!/bin/bash

# Selective macOS disk cleanup utility.
# Lets the user wipe one, several, or all of a curated set of cache and
# log directories that are safe to clean on macOS.

set -u

# Each entry: "label|path"
TARGETS=(
    "User caches|$HOME/Library/Caches"
    "User logs|$HOME/Library/Logs"
    "Trash|$HOME/.Trash"
    "Saved application state|$HOME/Library/Saved Application State"
    "Xcode DerivedData|$HOME/Library/Developer/Xcode/DerivedData"
    "Xcode Archives|$HOME/Library/Developer/Xcode/Archives"
    "iOS Simulator caches|$HOME/Library/Developer/CoreSimulator/Caches"
    "Homebrew cache|$HOME/Library/Caches/Homebrew"
    "npm cache|$HOME/.npm/_cacache"
    "Yarn cache|$HOME/Library/Caches/Yarn"
    "Pip cache|$HOME/Library/Caches/pip"
    "Gradle cache|$HOME/.gradle/caches"
    "System logs|/Library/Logs"
    "System caches|/Library/Caches"
)

if [ "$(uname)" != "Darwin" ]; then
    echo "Error: this script supports macOS (Darwin) only." >&2
    exit 1
fi

print_menu() {
    echo "macOS disk cleanup"
    echo "----------------------------------------------"
    echo "Select what to clean:"
    local i=1
    for entry in "${TARGETS[@]}"; do
        local label="${entry%%|*}"
        local path="${entry#*|}"
        local size="-"
        if [ -d "$path" ]; then
            size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
            [ -z "$size" ] && size="?"
        fi
        printf "%2d. %-26s [%6s] %s\n" "$i" "$label" "$size" "$path"
        i=$((i + 1))
    done
    echo
    echo " a. All of the above"
    echo " q. Quit"
    echo "----------------------------------------------"
}

confirm() {
    local prompt="$1"
    read -p "$prompt [y/N]: " ans
    case "$ans" in
        y | Y | yes | Yes | YES) return 0 ;;
        *) return 1 ;;
    esac
}

clean_target() {
    local entry="$1"
    local label="${entry%%|*}"
    local path="${entry#*|}"

    if [ ! -d "$path" ]; then
        echo "[skip] $label: $path not found."
        return
    fi

    if [ ! -w "$path" ]; then
        echo "[skip] $label: $path is not writable (try running with sudo)."
        return
    fi

    echo "[clean] $label: $path"
    # Remove contents but keep the parent directory itself.
    find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
}

print_menu
read -p "Enter your choice (e.g. 'a', '1,3,5'): " choice

selected=()
case "$choice" in
    q | Q) echo "Bye."; exit 0 ;;
    a | A | all | ALL)
        selected=("${TARGETS[@]}")
        ;;
    *)
        IFS=',' read -ra parts <<< "$choice"
        for raw in "${parts[@]}"; do
            n=$(echo "$raw" | tr -d '[:space:]')
            if [ -z "$n" ]; then
                continue
            fi
            if ! [[ "$n" =~ ^[0-9]+$ ]]; then
                echo "Error: invalid selection '$raw'." >&2
                exit 1
            fi
            idx=$((n - 1))
            if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#TARGETS[@]}" ]; then
                echo "Error: index out of range '$n'." >&2
                exit 1
            fi
            selected+=("${TARGETS[$idx]}")
        done
        ;;
esac

if [ "${#selected[@]}" -eq 0 ]; then
    echo "Nothing selected."
    exit 0
fi

echo
echo "About to clean:"
for entry in "${selected[@]}"; do
    echo " - ${entry%%|*} (${entry#*|})"
done
echo

if ! confirm "Proceed?"; then
    echo "Aborted."
    exit 0
fi

for entry in "${selected[@]}"; do
    clean_target "$entry"
done

echo "----------------------------------------------"
echo "Cleanup complete."
