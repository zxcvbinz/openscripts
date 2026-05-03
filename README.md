# openscripts

Collection of utility scripts (Apache, Django, macOS cleanup, SSH keys,
installers) exposed through a single entrypoint.

## Usage

```sh
./openscripts.sh <command> [arguments...]
```

Run `./openscripts.sh help` to list the available commands. Each command
forwards its arguments to the underlying script in `scripts/`.
