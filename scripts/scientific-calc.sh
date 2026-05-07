#!/bin/sh

# Scientific calculator: evaluates mathematical expressions from the
# command line using `bc -l` as the evaluation engine. Supports the
# four basic operations, exponentiation, parentheses, trigonometric
# functions, logarithms, and square roots. The script is POSIX sh
# compatible.

set -u

show_help() {
    cat <<EOF
Usage: $0 [command] [expression]

Available commands:
  eval <expression>     Evaluate a single mathematical expression.
  repl                  Interactive prompt; one expression per line.
  help                  Show this help message.

If no command is given but an expression is provided, the expression
is evaluated. If no arguments are given at all, the interactive REPL
is started.

Supported syntax:
  Operators:  +  -  *  /  %  ^   (parentheses for grouping)
  Functions:  sin(x)   cos(x)   tan(x)
              asin(x)  acos(x)  atan(x)
              ln(x)    log(x)   exp(x)
              sqrt(x)  abs(x)
  Constants:  pi  e

  Note: '^' accepts only integer exponents. For a real exponent y,
  use exp(y * ln(x)) instead of x^y.

Examples:
  $0 "2 + 3 * 4"
  $0 eval "sqrt(2)"
  $0 "sin(pi / 2)"
  $0 "log(1000)"
EOF
}

require_bc() {
    if ! command -v bc >/dev/null 2>&1; then
        echo "Error: 'bc' is required but was not found in PATH." >&2
        exit 127
    fi
    if ! command -v awk >/dev/null 2>&1; then
        echo "Error: 'awk' is required but was not found in PATH." >&2
        exit 127
    fi
}

# Translate a friendly expression (sin, cos, log, pi, ...) into a bc -l
# program. An awk tokenizer recognises identifiers so that, e.g., 'sin'
# inside 'asin' is not matched; unknown names are rejected up-front
# rather than being silently passed to bc.
translate_expression() {
    raw=$1

    # Reject characters that are not part of a numeric expression so we
    # cannot accidentally inject extra bc statements. Anything left over
    # after stripping the whitelist is invalid.
    leftover=$(printf '%s' "$raw" | tr -d '0-9A-Za-z_+*/%^(). ,	-')
    if [ -n "$leftover" ]; then
        echo "Error: expression contains invalid characters." >&2
        return 1
    fi

    translated=$(printf '%s\n' "$raw" | awk '
    {
        out = ""
        line = $0
        n = length(line)
        i = 1
        while (i <= n) {
            ch = substr(line, i, 1)
            if (ch ~ /[A-Za-z_]/) {
                j = i
                while (j <= n && substr(line, j, 1) ~ /[A-Za-z0-9_]/) {
                    j++
                }
                ident = substr(line, i, j - i)
                if      (ident == "sin")  out = out "s"
                else if (ident == "cos")  out = out "c"
                else if (ident == "tan")  out = out "_tan"
                else if (ident == "asin") out = out "_asin"
                else if (ident == "acos") out = out "_acos"
                else if (ident == "atan") out = out "a"
                else if (ident == "ln")   out = out "l"
                else if (ident == "log")  out = out "_log10"
                else if (ident == "exp")  out = out "e"
                else if (ident == "sqrt") out = out "sqrt"
                else if (ident == "abs")  out = out "_abs"
                else if (ident == "pi")   out = out "_pi"
                else if (ident == "e")    out = out "_e"
                else {
                    printf "ERR:unknown name %s\n", ident
                    exit 2
                }
                i = j
            } else {
                out = out ch
                i++
            }
        }
        print out
    }
    ')
    awk_rc=$?

    case $translated in
        ERR:*)
            echo "Error: ${translated#ERR:}" >&2
            return 1
            ;;
    esac
    if [ "$awk_rc" -ne 0 ]; then
        echo "Error: failed to parse expression." >&2
        return 1
    fi

    cat <<EOF
scale = 20
_pi = 4 * a(1)
_e = e(1)
define _tan(x) { return s(x) / c(x); }
define _asin(x) {
    if (x == 1) { return _pi / 2; }
    if (x == -1) { return -_pi / 2; }
    return a(x / sqrt(1 - x * x));
}
define _acos(x) { return _pi / 2 - _asin(x); }
define _log10(x) { return l(x) / l(10); }
define _abs(x) { if (x < 0) { return -x; }; return x; }
$translated
EOF
}

# Strip trailing zero fractional digits and a dangling decimal point so
# that exact integer results don't print as "4.00000000000000000000".
clean_number() {
    n=$1
    case $n in
        *.*)
            n=$(printf '%s' "$n" | sed -e 's/0*$//' -e 's/\.$//')
            ;;
    esac
    if [ -z "$n" ]; then
        n=0
    fi
    printf '%s\n' "$n"
}

evaluate() {
    expr=$1
    case $expr in
        '' | *[!\ \	]*) ;;
    esac
    if [ -z "$expr" ]; then
        echo "Error: empty expression." >&2
        return 1
    fi

    program=$(translate_expression "$expr") || return 1

    err_file=${TMPDIR:-/tmp}/calc_err_$$
    out=$(printf '%s\n' "$program" | bc -l 2>"$err_file")
    rc=$?
    if [ -s "$err_file" ]; then
        err=$(cat "$err_file")
    else
        err=""
    fi
    rm -f "$err_file"

    if [ "$rc" -ne 0 ] || [ -n "$err" ]; then
        if [ -n "$err" ]; then
            printf 'Error: %s\n' "$err" >&2
        else
            echo "Error: bc exited with status $rc." >&2
        fi
        return 1
    fi

    clean_number "$out"
}

cmd_eval() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 eval <expression>" >&2
        exit 1
    fi
    evaluate "$*"
}

cmd_repl() {
    echo "Scientific calculator. Type 'quit' to exit, 'help' for syntax."
    while :; do
        printf '> '
        if ! IFS= read -r line; then
            echo
            return 0
        fi
        case $line in
            quit | q | exit) echo "Bye."; return 0 ;;
            help | "?") show_help; continue ;;
            '') continue ;;
        esac
        evaluate "$line" || true
    done
}

if [ "$#" -lt 1 ]; then
    require_bc
    cmd_repl
    exit 0
fi

cmd=$1
case $cmd in
    -h | --help | help)
        show_help
        ;;
    eval)
        shift
        require_bc
        cmd_eval "$@"
        ;;
    repl | interactive)
        require_bc
        cmd_repl
        ;;
    *)
        # Treat the entire argument list as an expression.
        require_bc
        evaluate "$*"
        ;;
esac
