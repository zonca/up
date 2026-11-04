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
| Playwright CLI | npm |
| DeepSeek Harness (`dsh`) | pnpm global, plus profile plugin sync |
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

## DeepSeek Harness (dsh)

`dsh` is a global pnpm package, so the script updates it with
`pnpm add -g @deepseek-ai/dsh@latest` (it falls back to npm if that is where the
package lives).

A dsh profile pins the exact release of every `@deepseek-ai/dsh-*` plugin it
installs, and a locally linked bundle pins it in its own `peerDependencies`.
App-boot denies any plugin whose DSH requirement does not match the running
harness, so updating only the harness would silently disable web search or
sidebar bundles. When the release changes, `up` therefore also:

1. rewrites the pinned `@deepseek-ai/dsh-*` versions in every
   `$DSH_HOME/profiles/*/package.json`,
2. rewrites the matching `peerDependencies` of bundles linked with `link:` or
   `file:` (it prints the file so the change gets committed),
3. reinstalls the profile plugins, restoring the previous manifest if the
   install fails,
4. restarts `dsh-web.service` (unless `up` runs inside dsh itself, where the
   restart would kill the session).

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
