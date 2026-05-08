#!/bin/bash

# Installer di esempio per una skill Claude Code.
# Crea una directory ~/.claude/skills/<nome>/ con un file SKILL.md che
# contiene il frontmatter minimo richiesto da Claude Code (name + description).

set -e

SKILLS_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

read -p "Nome della skill (kebab-case, es. 'commit-helper'): " skill_name
case "$skill_name" in
    "" | *' '* | */*)
        echo "Errore: il nome è obbligatorio e non può contenere spazi o '/'." >&2
        exit 1
        ;;
esac

read -p "Descrizione breve della skill: " skill_desc
if [ -z "$skill_desc" ]; then
    echo "Errore: la descrizione è obbligatoria." >&2
    exit 1
fi

target_dir="$SKILLS_ROOT/$skill_name"
if [ -e "$target_dir" ]; then
    echo "Errore: la skill '$skill_name' esiste già in $target_dir." >&2
    exit 1
fi

mkdir -p "$target_dir"

cat > "$target_dir/SKILL.md" <<EOF
---
name: $skill_name
description: $skill_desc
---

# $skill_name

$skill_desc

## Quando usare questa skill

Descrivere qui i casi d'uso della skill.

## Istruzioni

Aggiungere qui le istruzioni dettagliate per l'agent.
EOF

echo "Skill creata in: $target_dir"
echo "Modifica $target_dir/SKILL.md per personalizzarla."
