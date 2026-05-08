# openscripts

Collection of utility shell scripts (Apache, Django, macOS cleanup, SSH keys,
dotfiles, dev-tools check-up, installers) exposed through a single
dispatcher: `openscripts.sh`.

Each command is an independent, self-contained script under `scripts/`.
The dispatcher takes the first argument as the command name and forwards
every remaining argument to the underlying script unchanged.

## Requirements

- Bash 4+ (`/bin/bash` or `/usr/bin/env bash`).
- Standard Unix utilities: `awk`, `sed`, `grep`, `tr`, `find`, `stat`, `du`.
- Per-command requirements:
  - `apache`: Apache HTTP Server (`apachectl`), `certbot` (only for the SSL flow), root privileges.
  - `django`: a project with `manage.py` in the current directory and `python` on `PATH`.
  - `macos-cleanup`: macOS (Darwin) only.
  - `ssh`, `ssh-keygen`, `ssh-keyremove`: `ssh-keygen` from OpenSSH.
  - `calc`: `bc` (with `-l`) and `awk`.
  - `devtools-checkup`: optional — only the tools you want to inspect.
  - `install-lazydocker`: `curl`, `tar`, `sudo` (Linux x86_64).
  - `install-openscripts`: write access (or `sudo`) for `/usr/local/bin`.

No third-party libraries or package managers are required to run the
dispatcher itself.

## Installation

Clone the repository and make sure `openscripts.sh` is executable:

```sh
git clone <repository-url> openscripts
cd openscripts
chmod +x openscripts.sh
```

Optionally, symlink the dispatcher into `/usr/local/bin` so it becomes
available as the `openscripts` command from anywhere:

```sh
./openscripts.sh install-openscripts install
```

To remove the symlink later:

```sh
./openscripts.sh install-openscripts uninstall
```

To check whether the symlink is in place:

```sh
./openscripts.sh install-openscripts status
```

## Usage

```sh
./openscripts.sh <command> [arguments...]
```

List every available command:

```sh
./openscripts.sh help
```

Each command also accepts `-h` / `--help` / `help` and prints its own
detailed usage.

### Examples

```sh
# Show the dispatcher's command list.
./openscripts.sh help

# Show the help for a specific command.
./openscripts.sh ssh-keygen --help
./openscripts.sh caesar help

# Generate a new Ed25519 SSH key for GitHub and register it in ~/.ssh/config.
./openscripts.sh ssh-keygen --email me@example.com --host github.com

# Remove that key pair, its config block, and its known_hosts entries.
./openscripts.sh ssh-keyremove --name id_ed25519 --host github.com --yes

# Run an ad-hoc calculation.
./openscripts.sh calc "sin(pi / 2) + sqrt(2)"

# Encrypt a string with the Caesar cipher.
./openscripts.sh caesar encrypt 3 "Hello, World!"

# Back up dotfiles into ~/dotfiles-backup.
./openscripts.sh dotfiles export ~/dotfiles-backup

# Run the developer-tools check-up.
./openscripts.sh devtools-checkup
```

## Available commands

| Command              | Description                                                         |
| -------------------- | ------------------------------------------------------------------- |
| `apache`             | Manage Apache virtual hosts (sites + SSL). Requires root.           |
| `django`             | Run common Django management commands (migrate, start, ...).        |
| `macos-cleanup`      | Selective macOS disk cleanup (caches, logs, build artifacts).       |
| `ssh`                | Interactive local SSH key manager (list, view, create, fix perms).  |
| `ssh-keygen`         | Non-interactive SSH key generator + optional `~/.ssh/config` block. |
| `ssh-keyremove`      | Non-interactive SSH key removal + config / known\_hosts cleanup.    |
| `caesar`             | Encrypt/decrypt text with the Caesar cipher.                        |
| `calc`               | Scientific calculator (arithmetic, trig, log, sqrt) on top of `bc`. |
| `ai-skills`          | List and install AI skills (Claude Code skills scaffold, ...).      |
| `devtools-checkup`   | Check installed dev tools (Git, Xcode, Node, Python, Ruby, Docker). |
| `dotfiles`           | Backup/restore curated dotfiles (`.zshrc`, `.gitconfig`, ...).      |
| `install-lazydocker` | Install [lazydocker](https://github.com/jesseduffield/lazydocker).  |
| `install-openscripts`| Symlink `openscripts.sh` into `/usr/local/bin`.                     |

Run `./openscripts.sh <command> --help` to see the full options and
examples of each script.

## Project layout

```
openscripts/
├── openscripts.sh              # Dispatcher / entrypoint
├── scripts/                    # One script per command
│   ├── apache-manage.sh
│   ├── django-manage.sh
│   ├── ...
│   └── installers/             # Installer scripts
│       ├── install-lazydocker.sh
│       ├── install-openscripts.sh
│       └── ai-skills/          # Per-skill installers
└── README.md
```

## Adding a new command

1. Drop a new executable script in `scripts/` (or `scripts/installers/`)
   following the naming convention `<topic>-manage.sh` or `<topic>.sh`.
2. Mark it executable: `chmod +x scripts/<your-script>.sh`.
3. Make sure it has its own `--help` / `help` handler and validates its
   arguments.
4. Register it in the `COMMANDS` array in `openscripts.sh` using the
   `name|relative path|description` format.

## License

See [LICENSE](LICENSE).
