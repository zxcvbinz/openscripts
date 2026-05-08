#!/bin/bash

# openscripts: single entrypoint that dispatches to the project's utility
# scripts under ./scripts. Each subcommand maps to one underlying script
# and forwards remaining arguments to it unchanged.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Each entry: "name|relative path|description"
COMMANDS=(
    "apache|scripts/apache-manage.sh|Manage Apache virtual hosts (sites + SSL)"
    "django|scripts/django-manage.sh|Run Django management commands"
    "macos-cleanup|scripts/macos-cleanup.sh|Selective macOS disk cleanup"
    "ssh|scripts/ssh-manage.sh|Manage local SSH keys"
    "ssh-keygen|scripts/ssh-keygen.sh|Generate a new SSH key (Ed25519/RSA) and update SSH config"
    "ssh-agent|scripts/ssh-agent-manage.sh|Select an SSH key, start ssh-agent and load it into memory"
    "ssh-keyremove|scripts/ssh-keyremove.sh|Remove an SSH key pair and clean SSH config / known_hosts"
    "caesar|scripts/caesar-cipher.sh|Encrypt or decrypt text with the Caesar cipher"
    "calc|scripts/scientific-calc.sh|Scientific calculator (arithmetic, trig, log, sqrt)"
    "ai-skills|scripts/ai-skills-manage.sh|List and install AI skills"
    "devtools-checkup|scripts/devtools-checkup.sh|Check installed dev tools (Git, Xcode, Node, Python, Ruby, Docker)"
    "dotfiles|scripts/dotfiles-manage.sh|Backup/restore dev environment dotfiles (.zshrc, .gitconfig, .vimrc, ...)"
    "install-lazydocker|scripts/installers/install-lazydocker.sh|Install lazydocker"
    "install-openscripts|scripts/installers/install-openscripts.sh|Symlink openscripts to /usr/local/bin (install/uninstall/status)"
)

show_help() {
    echo "Usage: $0 <command> [arguments...]"
    echo
    echo "Available commands:"
    local entry name rest desc
    for entry in "${COMMANDS[@]}"; do
        name="${entry%%|*}"
        rest="${entry#*|}"
        desc="${rest#*|}"
        printf "  %-20s %s\n" "$name" "$desc"
    done
    echo
    echo "Run '$0 help' to show this message."
}

if [ "$#" -lt 1 ]; then
    show_help
    exit 1
fi

cmd="$1"
shift

case "$cmd" in
    -h | --help | help)
        show_help
        exit 0
        ;;
esac

for entry in "${COMMANDS[@]}"; do
    name="${entry%%|*}"
    rest="${entry#*|}"
    path="${rest%%|*}"
    if [ "$cmd" = "$name" ]; then
        exec bash "$SCRIPT_DIR/$path" "$@"
    fi
done

echo "Error: unknown command '$cmd'." >&2
echo
show_help
exit 1
