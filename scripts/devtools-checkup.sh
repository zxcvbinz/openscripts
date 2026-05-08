#!/bin/bash

# Diagnostic check-up for common developer tools. For each tool it
# reports whether the binary is installed, its current version, and
# whether that version meets a minimum recommended baseline. Exits with
# a non-zero status when something is missing or outdated, so it can be
# wired into CI or pre-flight scripts.

set -u

TOTAL=0
OK_COUNT=0
OUTDATED_COUNT=0
MISSING_COUNT=0

STATUS_OK="[OK]"
STATUS_OUTDATED="[OUTDATED]"
STATUS_MISSING="[MISSING]"

show_help() {
    cat <<EOF
Usage: $0 [command]

Available commands:
  run        Run the developer-tools check-up (default).
  list       List the tools and their minimum recommended versions.
  help       Show this help message.

The check-up inspects the following tools and reports, for each one,
whether it is installed, its current version, and whether it meets the
minimum recommended version:

  Git, Xcode (macOS only), Node.js, Python, Ruby, Docker.

Exit status is 0 when every tool meets its minimum version, otherwise 1.
EOF
}

# Compare two dotted version strings using 'sort -V'. Returns 0 when
# $1 >= $2. An empty $2 means "no minimum required" and is treated as
# always satisfied.
version_ge() {
    local current="$1"
    local min="$2"
    [ -z "$min" ] && return 0
    local lower
    lower=$(printf '%s\n%s\n' "$current" "$min" | sort -V 2>/dev/null | head -n1)
    [ "$lower" = "$min" ]
}

# Pull the first dotted version-looking token (e.g. 1.2 or 1.2.3) out
# of an arbitrary version-banner string.
extract_version() {
    printf '%s' "$1" | awk '{
        if (match($0, /[0-9]+\.[0-9]+(\.[0-9]+)?/)) {
            print substr($0, RSTART, RLENGTH)
            exit
        }
    }'
}

print_row() {
    local status="$1" name="$2" current="$3" min="$4" hint="$5"
    local min_display="${min:-any}"
    if [ -z "$hint" ]; then
        printf '  %-11s %-8s %-14s (min %s)\n' \
            "$status" "$name" "$current" "$min_display"
    else
        printf '  %-11s %-8s %-14s (min %s)  -> %s\n' \
            "$status" "$name" "$current" "$min_display" "$hint"
    fi
}

report_missing() {
    local name="$1" hint="$2"
    TOTAL=$((TOTAL + 1))
    MISSING_COUNT=$((MISSING_COUNT + 1))
    print_row "$STATUS_MISSING" "$name" "-" "" "$hint"
}

report_version() {
    local name="$1" current="$2" min="$3" hint="$4"
    TOTAL=$((TOTAL + 1))
    if [ -z "$current" ]; then
        OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
        print_row "$STATUS_OUTDATED" "$name" "?" "$min" \
            "could not parse version; $hint"
        return
    fi
    if version_ge "$current" "$min"; then
        OK_COUNT=$((OK_COUNT + 1))
        print_row "$STATUS_OK" "$name" "$current" "$min" ""
    else
        OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
        print_row "$STATUS_OUTDATED" "$name" "$current" "$min" "$hint"
    fi
}

check_git() {
    local min="2.30.0"
    local hint="install/update Git: https://git-scm.com/downloads"
    if ! command -v git >/dev/null 2>&1; then
        report_missing "Git" "$hint"
        return
    fi
    local raw current
    raw=$(git --version 2>/dev/null)
    current=$(extract_version "$raw")
    report_version "Git" "$current" "$min" "$hint"
}

check_xcode() {
    # Xcode only ships on macOS. On other systems, report it as
    # not-applicable so the row stays in the table for clarity but
    # does not count as a failure.
    if [ "$(uname 2>/dev/null)" != "Darwin" ]; then
        TOTAL=$((TOTAL + 1))
        OK_COUNT=$((OK_COUNT + 1))
        print_row "$STATUS_OK" "Xcode" "n/a" "" "skipped: not macOS"
        return
    fi

    local min="14.0"
    local hint="install Xcode from the App Store"
    local clt_hint="install Command Line Tools: 'xcode-select --install'"

    if ! command -v xcodebuild >/dev/null 2>&1; then
        # Full Xcode is missing, but the Command Line Tools alone may
        # still be enough for many workflows. Surface that distinction
        # rather than reporting a hard miss.
        if command -v xcode-select >/dev/null 2>&1 \
           && xcode-select -p >/dev/null 2>&1; then
            TOTAL=$((TOTAL + 1))
            OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
            local clt_path
            clt_path=$(xcode-select -p 2>/dev/null)
            print_row "$STATUS_OUTDATED" "Xcode" "CLT only" "$min" \
                "full Xcode not installed (CLT at $clt_path)"
            return
        fi
        report_missing "Xcode" "$clt_hint or $hint"
        return
    fi

    local raw current
    raw=$(xcodebuild -version 2>/dev/null | head -n1)
    current=$(extract_version "$raw")
    report_version "Xcode" "$current" "$min" "$hint"
}

check_node() {
    local min="18.0.0"
    local hint="install/update Node.js: https://nodejs.org/"
    if ! command -v node >/dev/null 2>&1; then
        report_missing "Node" "$hint"
        return
    fi
    local raw current
    raw=$(node --version 2>/dev/null)
    current=$(extract_version "$raw")
    report_version "Node" "$current" "$min" "$hint"
}

check_python() {
    local min="3.9.0"
    local hint="install/update Python 3: https://www.python.org/"
    local bin=""
    # Prefer python3; fall back to a bare 'python' only if it is a
    # Python 3 build (Python 2 is end-of-life).
    if command -v python3 >/dev/null 2>&1; then
        bin="python3"
    elif command -v python >/dev/null 2>&1; then
        bin="python"
    fi
    if [ -z "$bin" ]; then
        report_missing "Python" "$hint"
        return
    fi
    local raw current
    raw=$("$bin" --version 2>&1)
    current=$(extract_version "$raw")
    report_version "Python" "$current" "$min" "$hint"
}

check_ruby() {
    local min="3.0.0"
    local hint="install/update Ruby: https://www.ruby-lang.org/"
    if ! command -v ruby >/dev/null 2>&1; then
        report_missing "Ruby" "$hint"
        return
    fi
    local raw current
    raw=$(ruby --version 2>/dev/null)
    current=$(extract_version "$raw")
    report_version "Ruby" "$current" "$min" "$hint"
}

check_docker() {
    local min="24.0.0"
    local hint="install/update Docker: https://www.docker.com/"
    if ! command -v docker >/dev/null 2>&1; then
        report_missing "Docker" "$hint"
        return
    fi
    local raw current
    raw=$(docker --version 2>/dev/null)
    current=$(extract_version "$raw")
    report_version "Docker" "$current" "$min" "$hint"
}

print_header() {
    printf 'Developer tools check-up\n'
    printf -- '----------------------------------------------------------------------\n'
}

print_summary() {
    printf -- '----------------------------------------------------------------------\n'
    printf 'Summary: %d checked, %d OK, %d outdated, %d missing.\n' \
        "$TOTAL" "$OK_COUNT" "$OUTDATED_COUNT" "$MISSING_COUNT"
}

list_tools() {
    cat <<EOF
Tools inspected by the check-up:

  Git      (min 2.30.0)
  Xcode    (min 14.0,  macOS only)
  Node.js  (min 18.0.0)
  Python   (min 3.9.0, python3 preferred)
  Ruby     (min 3.0.0)
  Docker   (min 24.0.0)
EOF
}

cmd_run() {
    print_header
    check_git
    check_xcode
    check_node
    check_python
    check_ruby
    check_docker
    print_summary

    if [ "$MISSING_COUNT" -gt 0 ] || [ "$OUTDATED_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}

cmd="${1:-run}"
case "$cmd" in
    -h | --help | help)
        show_help
        ;;
    list)
        list_tools
        ;;
    run | check | checkup)
        cmd_run
        exit $?
        ;;
    *)
        echo "Error: unknown command '$cmd'." >&2
        echo
        show_help
        exit 1
        ;;
esac
