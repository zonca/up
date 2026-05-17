# AGENT.md

## Project overview

`up.sh` is a single-file bash script that provides an `up()` shell function. It updates system packages (apt) and AI coding assistants (npm, CLI) in one command and prints a before/after version report.

## Key design decisions

- Single file: everything lives in `up.sh` — no modules, no dependencies beyond standard CLI tools.
- Self-update: `_up_self_update()` runs at the top of `up()` and pulls the latest version from GitHub if it differs.
- Only updates packages that are actually installed (checks before attempting npm install).

## Structure

- `up.sh` — the entire script. Contains:
  - `_up_self_update()` — downloads latest from GitHub, replaces in-place if changed
  - `up()` — main function: check versions, update apt, update npm, update CLIs, print report

## When modifying

- Keep it as a single file. Do not split into modules.
- All npm packages are in the `npm_pkgs` array at the top of `up()`.
- The self-update uses `$BASH_SOURCE[0]` to find its own path — do not break this.
- Test by running `source up.sh && up` — the function must be sourced, not executed directly.

## Testing

```bash
source up.sh
up
```

No automated tests — manual verification only.
