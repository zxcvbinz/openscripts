#!/bin/bash

# AI skills manager: shows the catalog of installable AI skills and runs
# the corresponding installer in scripts/installers/ai-skills/.
# To register a new skill, drop its installer in that directory and add an
# entry to the SKILLS array below.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/installers/ai-skills"

# Each entry: "name|installer filename|description"
SKILLS=(
    "claude-skill-scaffold|install-claude-skill-scaffold.sh|Scaffold di una nuova skill Claude Code in ~/.claude/skills"
)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

action_list() {
    echo "Skill AI disponibili"
    echo "----------------------------------------------"

    if [ "${#SKILLS[@]}" -eq 0 ]; then
        echo "Nessuna skill registrata."
        return
    fi

    printf "%-30s %s\n" "NOME" "DESCRIZIONE"
    printf "%-30s %s\n" "----" "-----------"
    local entry name rest desc
    for entry in "${SKILLS[@]}"; do
        name="${entry%%|*}"
        rest="${entry#*|}"
        desc="${rest#*|}"
        printf "%-30s %s\n" "$name" "$desc"
    done
}

action_install() {
    if [ "${#SKILLS[@]}" -eq 0 ]; then
        echo "Nessuna skill installabile."
        return
    fi

    echo "Skill AI installabili:"
    local entry name rest path desc i=1 paths=()
    for entry in "${SKILLS[@]}"; do
        name="${entry%%|*}"
        rest="${entry#*|}"
        path="${rest%%|*}"
        desc="${rest#*|}"
        printf "%2d. %-30s %s\n" "$i" "$name" "$desc"
        paths+=("$path")
        i=$((i + 1))
    done

    read -p "Numero della skill da installare (vuoto per annullare): " choice
    [ -z "$choice" ] && return
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo "Errore: numero non valido." >&2
        return
    fi
    local idx=$((choice - 1))
    if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#paths[@]}" ]; then
        echo "Errore: scelta fuori range." >&2
        return
    fi

    local installer="$SKILLS_DIR/${paths[$idx]}"
    if [ ! -f "$installer" ]; then
        echo "Errore: installer non trovato: $installer" >&2
        return
    fi

    echo "----------------------------------------------"
    echo "Avvio installazione: ${paths[$idx]}"
    echo "----------------------------------------------"
    if ! bash "$installer"; then
        echo "Errore: installazione fallita." >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------

print_menu() {
    echo "Gestione skill AI"
    echo "----------------------------------------------"
    echo "  1. Visualizza skill disponibili"
    echo "  2. Installa una skill"
    echo "  q. Esci"
    echo "----------------------------------------------"
}

print_menu
read -p "Scelta: " choice

case "$choice" in
    1) action_list ;;
    2) action_install || exit $? ;;
    q | Q) echo "Bye."; exit 0 ;;
    *) echo "Errore: opzione non valida." >&2; exit 1 ;;
esac

echo "----------------------------------------------"
echo "Done."
