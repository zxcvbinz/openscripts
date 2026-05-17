#!/usr/bin/env bats

# Smoke tests for the openscripts.sh dispatcher.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DISPATCHER="$REPO_ROOT/openscripts.sh"
}

@test "dispatcher exists and is executable" {
    [ -x "$DISPATCHER" ]
}

@test "no arguments prints usage and exits non-zero" {
    run "$DISPATCHER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Available commands:"* ]]
}

@test "help subcommand prints usage and exits zero" {
    run "$DISPATCHER" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Available commands:"* ]]
}

@test "--help flag prints usage and exits zero" {
    run "$DISPATCHER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "-h flag prints usage and exits zero" {
    run "$DISPATCHER" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unknown command prints error and exits non-zero" {
    run "$DISPATCHER" definitely-not-a-real-command
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown command"* ]]
}

@test "every registered command points to an existing executable script" {
    while IFS='|' read -r name path desc; do
        [ -n "$name" ] || continue
        [ -f "$REPO_ROOT/$path" ] || {
            echo "Missing script for '$name': $path"
            return 1
        }
        [ -x "$REPO_ROOT/$path" ] || {
            echo "Script for '$name' is not executable: $path"
            return 1
        }
    done < <(
        awk '
            /^COMMANDS=\(/ { in_block = 1; next }
            in_block && /^\)/ { exit }
            in_block {
                line = $0
                sub(/^[[:space:]]*"/, "", line)
                sub(/"[[:space:]]*$/, "", line)
                if (length(line) > 0) print line
            }
        ' "$DISPATCHER"
    )
}

@test "every script under scripts/ starts with a valid shell shebang" {
    while IFS= read -r -d '' file; do
        head -n 1 "$file" | grep -Eq '^#!(/bin/bash|/usr/bin/env bash|/bin/sh|/usr/bin/env sh)' || {
            echo "Missing or invalid shebang in $file"
            return 1
        }
    done < <(find "$REPO_ROOT/scripts" -type f -name '*.sh' -print0)
}

@test "every script under scripts/ is executable" {
    while IFS= read -r -d '' file; do
        [ -x "$file" ] || {
            echo "Script is not executable: $file"
            return 1
        }
    done < <(find "$REPO_ROOT/scripts" -type f -name '*.sh' -print0)
}
