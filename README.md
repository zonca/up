# up

A shell function that updates system packages and AI coding assistants in one command, with before/after version reporting.

**Blog post:** [up: One Command to Update All My AI Tools](https://zonca.dev/posts/2026-05-17-up-shell-function-update-all-ai-tools.html)

## What it updates

| Tool | Method |
|------|--------|
| System packages | `apt upgrade` |
| Gemini CLI | npm |
| Codex | npm |
| OpenCode AI | npm |
| Crush | npm |
| Qwen Code | npm |
| Cline | npm |
| Bitwarden CLI | npm |
| GitHub Copilot | npm |
| gog | GitHub release via `gh` |
| Claude Code | `claude upgrade` |

## Install

```bash
curl -o ~/.up.sh https://raw.githubusercontent.com/zonca/up/main/up.sh
echo 'source ~/.up.sh' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```bash
up
```

Output includes a version report showing old and new versions for every updated package.

## Self-update

The script checks for a newer version on GitHub each time it runs and updates itself automatically.

## Schedule daily runs

Add a cron job to run it every morning:

```bash
echo '0 7 * * * /home/$USER/.up.sh' | crontab -
```

## Customize

Edit the `npm_pkgs` array in `up.sh` to add or remove npm packages:

```bash
local npm_pkgs=("@google/gemini-cli" "@openai/codex" "opencode-ai")
```

## Requirements

- Ubuntu/Debian (apt)
- Node.js/npm (for npm packages)
- `gh` CLI (for gog updates)
- `curl` (for self-update)

## License

MIT
