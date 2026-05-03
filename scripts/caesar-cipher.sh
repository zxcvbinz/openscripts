#!/bin/bash

# Caesar cipher: encrypt or decrypt text by shifting letters by a numeric key.
# Preserves case, spaces, punctuation, and any non-letter characters.

set -u

show_help() {
    cat <<EOF
Usage: $0 [command] [arguments]

Available commands:
  encrypt <shift> [text]     Encrypt text with the given numeric shift.
  decrypt <shift> [text]     Decrypt text with the given numeric shift.
  chat                       Interactive loop to encrypt/decrypt messages.
  help                       Show this help message.

If <text> is omitted from encrypt/decrypt, the text is read from stdin.
With no command, the interactive chat is started.

Examples:
  $0
  $0 chat
  $0 encrypt 3 "Hello, World!"
  $0 decrypt 3 "Khoor, Zruog!"
  echo "Hello" | $0 encrypt 5
EOF
}

# Validate that the argument is a (possibly negative) decimal integer.
# Returns 0 on success, 1 on failure (and prints an error to stderr).
validate_shift() {
    local s="$1"
    if ! [[ "$s" =~ ^-?[0-9]+$ ]]; then
        echo "Error: shift must be an integer, got '$s'." >&2
        return 1
    fi
}

# Convert a validated shift string to a normalized base-10 integer
# in the range [0, 25]. Avoids octal interpretation for e.g. "08".
normalize_shift() {
    local raw="$1"
    local val
    if [[ "$raw" == -* ]]; then
        val=$(( -10#${raw#-} ))
    else
        val=$(( 10#$raw ))
    fi
    echo $(( ((val % 26) + 26) % 26 ))
}

# Apply a Caesar shift to a string. Letters are shifted modulo 26,
# upper- and lowercase are preserved independently, and any other
# characters (spaces, digits, punctuation, UTF-8 bytes) pass through
# unchanged.
# Args: <text> <normalized-shift-in-0-25>
caesar_shift() {
    local text="$1"
    local shift="$2"
    local result=""
    local i char code shifted out

    for (( i=0; i<${#text}; i++ )); do
        char="${text:$i:1}"
        printf -v code "%d" "'$char"

        if (( code >= 65 && code <= 90 )); then
            shifted=$(( (code - 65 + shift) % 26 + 65 ))
            printf -v out "\\$(printf '%03o' "$shifted")"
            result+="$out"
        elif (( code >= 97 && code <= 122 )); then
            shifted=$(( (code - 97 + shift) % 26 + 97 ))
            printf -v out "\\$(printf '%03o' "$shifted")"
            result+="$out"
        else
            result+="$char"
        fi
    done

    printf '%s\n' "$result"
}

cmd_encrypt() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 encrypt <shift> [text]" >&2
        exit 1
    fi
    local shift_arg="$1"
    shift
    validate_shift "$shift_arg" || exit 1

    local text
    if [ "$#" -ge 1 ]; then
        text="$*"
    else
        IFS= read -r text || true
    fi

    caesar_shift "$text" "$(normalize_shift "$shift_arg")"
}

cmd_decrypt() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 decrypt <shift> [text]" >&2
        exit 1
    fi
    local shift_arg="$1"
    shift
    validate_shift "$shift_arg" || exit 1

    local text
    if [ "$#" -ge 1 ]; then
        text="$*"
    else
        IFS= read -r text || true
    fi

    # Decrypting with shift k is the same as encrypting with shift -k.
    caesar_shift "$text" "$(normalize_shift "-$shift_arg")"
}

cmd_chat() {
    echo "Caesar cipher chat."
    echo "Type 'quit' (or press Ctrl+D) at the operation prompt to exit."
    echo

    local op shift_key text norm
    while true; do
        if ! IFS= read -r -p "Operation [encrypt/decrypt/quit]: " op; then
            echo
            return 0
        fi
        case "$op" in
            quit | q | exit) echo "Bye."; return 0 ;;
            encrypt | e | enc) op="encrypt" ;;
            decrypt | d | dec) op="decrypt" ;;
            "") continue ;;
            *)
                echo "Unknown operation '$op'. Try encrypt, decrypt, or quit."
                continue
                ;;
        esac

        if ! IFS= read -r -p "Shift key (integer): " shift_key; then
            echo
            return 0
        fi
        if ! validate_shift "$shift_key"; then
            continue
        fi

        if ! IFS= read -r -p "Text: " text; then
            echo
            return 0
        fi

        if [ "$op" = "decrypt" ]; then
            norm=$(normalize_shift "-$shift_key")
        else
            norm=$(normalize_shift "$shift_key")
        fi

        printf 'Result: '
        caesar_shift "$text" "$norm"
        echo
    done
}

if [ "$#" -lt 1 ]; then
    cmd_chat
    exit 0
fi

cmd="$1"
shift

case "$cmd" in
    -h | --help | help)
        show_help
        ;;
    encrypt)
        cmd_encrypt "$@"
        ;;
    decrypt)
        cmd_decrypt "$@"
        ;;
    chat | interactive)
        cmd_chat
        ;;
    *)
        echo "Error: unknown command '$cmd'." >&2
        echo
        show_help
        exit 1
        ;;
esac
