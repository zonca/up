#!/usr/bin/env bash
# up.sh — Update system packages and AI coding assistants with version reporting
# Repo: https://github.com/zonca/up
# Install: curl -o ~/.up.sh https://raw.githubusercontent.com/zonca/up/main/up.sh
#          echo "source ~/.up.sh" >> ~/.bashrc

UP_REPO="zonca/up"
UP_SCRIPT_PATH="${BASH_SOURCE[0]}"

_up_self_update() {
    local tmp
    tmp=$(mktemp)
    if curl -fsSL "https://raw.githubusercontent.com/$UP_REPO/main/up.sh" -o "$tmp" 2>/dev/null; then
        if ! diff -q "$tmp" "$UP_SCRIPT_PATH" >/dev/null 2>&1; then
            echo "up.sh: New version found, updating..."
            cp "$tmp" "$UP_SCRIPT_PATH"
            echo "up.sh: Updated successfully."
        fi
        rm -f "$tmp"
    else
        echo "up.sh: Could not check for updates." >&2
        rm -f "$tmp"
    fi
}

# ---------------------------------------------------------------------------
# DeepSeek Harness (dsh)
#
# dsh is a global pnpm package. A profile pins the exact release of every
# @deepseek-ai/dsh-* plugin it installs, and a bundle linked from a working tree
# pins it in its own peerDependencies; app-boot denies any plugin whose DSH
# requirement does not match the running harness. Updating only the harness
# would disable those plugins at the next boot, so the profiles are synced and
# the web service restarted in the same run.
# ---------------------------------------------------------------------------

DSH_PACKAGE="@deepseek-ai/dsh"

_dsh_version() {
    dsh --version 2>/dev/null | head -1
}

# Bump the harness release in one profile manifest and in the manifests of the
# bundles it links from disk. Prints every change. Exit 0 when the profile's own
# dependencies changed (a pnpm install is then required), 1 when nothing did,
# 2 on error.
_dsh_sync_manifest() { # <manifest> <release>
    node - "$1" "$2" <<'NODE'
const fs = require('node:fs')
const path = require('node:path')

const [manifestFile, release] = process.argv.slice(2)

const isHarnessPackage = (name) => {
  if (!name.startsWith('@deepseek-ai/')) return false
  const rest = name.slice('@deepseek-ai/'.length)
  return rest === 'dsh' || rest.startsWith('dsh-')
}
const isExactVersion = (spec) => /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(spec || '')
const write = (file, json) => fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n')
const report = (message) => console.log(`  ${message}`)

try {
  const manifestPath = path.resolve(manifestFile)
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  let dependenciesChanged = false

  for (const field of ['dependencies', 'devDependencies', 'optionalDependencies']) {
    const dependencies = manifest[field]
    if (!dependencies) continue
    for (const [name, spec] of Object.entries(dependencies)) {
      if (!isHarnessPackage(name) || !isExactVersion(spec) || spec === release) continue
      dependencies[name] = release
      dependenciesChanged = true
      report(`${name} ${spec} -> ${release}`)
    }
  }
  if (dependenciesChanged) write(manifestPath, manifest)

  // A bundle linked from a working tree (link:/file:) is outside pnpm's control,
  // so its peers are bumped where the bundle lives.
  for (const field of ['dependencies', 'devDependencies']) {
    const dependencies = manifest[field]
    if (!dependencies) continue
    for (const [name, spec] of Object.entries(dependencies)) {
      const match = /^(?:link|file):(.+)$/.exec(spec || '')
      if (!match) continue
      const bundleFile = path.join(path.resolve(path.dirname(manifestPath), match[1]), 'package.json')
      if (!fs.existsSync(bundleFile)) {
        report(`warning: ${name} is linked from ${bundleFile}, which does not exist`)
        continue
      }
      const bundle = JSON.parse(fs.readFileSync(bundleFile, 'utf8'))
      const peers = bundle.peerDependencies
      if (!peers) continue
      let peersChanged = false
      for (const [peer, peerSpec] of Object.entries(peers)) {
        if (!isHarnessPackage(peer) || !isExactVersion(peerSpec) || peerSpec === release) continue
        peers[peer] = release
        peersChanged = true
        report(`linked ${name}: peer ${peer} ${peerSpec} -> ${release}`)
      }
      if (peersChanged) {
        write(bundleFile, bundle)
        report(`${bundleFile} updated: commit it in its own repository`)
      }
    }
  }

  process.exit(dependenciesChanged ? 0 : 1)
} catch (error) {
  console.error(`  error: ${error.message}`)
  process.exit(2)
}
NODE
}

_dsh_restart_web() {
    command -v systemctl >/dev/null 2>&1 || return 0
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    systemctl --user is-active --quiet dsh-web.service 2>/dev/null || return 0
    if [ -n "${DSH_SESSION_ID:-}" ]; then
        # This shell is a child of the service we would restart; let the running
        # session finish and restart from a plain terminal instead.
        echo "NOTE: dsh is running this shell; restart the web UI when convenient:"
        echo "      systemctl --user restart dsh-web.service"
        return 0
    fi
    echo "Restarting dsh-web.service..."
    if systemctl --user restart dsh-web.service && sleep 2 && systemctl --user is-active --quiet dsh-web.service; then
        echo "dsh-web.service restarted."
    else
        echo "WARNING: dsh-web.service did not come back up; check: journalctl --user -u dsh-web.service -n 50" >&2
    fi
}

_up_dsh() {
    local old new manager home manifest profile name status backup

    old=$(_dsh_version)

    if command -v pnpm >/dev/null 2>&1 && pnpm ls -g --depth 0 2>/dev/null | grep -q "$DSH_PACKAGE@"; then
        manager=pnpm
    elif command -v npm >/dev/null 2>&1 && npm ls -g --depth 0 2>/dev/null | grep -q "$DSH_PACKAGE@"; then
        manager=npm
    else
        echo "DeepSeek Harness: $DSH_PACKAGE is not in a global pnpm/npm install; skipping its update." >&2
        return 0
    fi

    echo "Updating DeepSeek Harness (dsh) with $manager..."
    if [ "$manager" = pnpm ]; then
        pnpm add -g "$DSH_PACKAGE@latest" || { echo "ERROR: dsh update failed." >&2; return 0; }
    else
        npm install -g "$DSH_PACKAGE@latest" --force || { echo "ERROR: dsh update failed." >&2; return 0; }
    fi

    new=$(_dsh_version)
    if [ -z "$new" ]; then
        echo "ERROR: could not read the dsh version after the update." >&2
        return 0
    fi
    if [ "$new" = "$old" ]; then
        echo "DeepSeek Harness already up to date ($old)."
        return 0
    fi
    echo "DeepSeek Harness: $old -> $new; syncing profiles..."

    home="${DSH_HOME:-$HOME/.dsh}"
    for manifest in "$home"/profiles/*/package.json; do
        [ -f "$manifest" ] || continue
        profile="${manifest%/package.json}"
        name="${profile##*/}"
        echo "dsh profile $name:"
        backup=$(mktemp -d)
        cp "$manifest" "$backup/package.json"
        [ -f "$profile/pnpm-lock.yaml" ] && cp "$profile/pnpm-lock.yaml" "$backup/pnpm-lock.yaml"
        _dsh_sync_manifest "$manifest" "$new"
        status=$?
        if [ "$status" -eq 0 ]; then
            if dsh plugin --profile "$name" install; then
                echo "  plugins reinstalled for dsh $new"
            else
                echo "  WARNING: plugin install failed; restoring the previous manifest" >&2
                cp "$backup/package.json" "$manifest"
                [ -f "$backup/pnpm-lock.yaml" ] && cp "$backup/pnpm-lock.yaml" "$profile/pnpm-lock.yaml"
            fi
        elif [ "$status" -ne 1 ]; then
            echo "  WARNING: manifest sync failed; restoring the previous manifest" >&2
            cp "$backup/package.json" "$manifest"
        else
            echo "  no pinned plugin versions to change"
        fi
        rm -rf "$backup"
    done

    _dsh_restart_web
}

up() {
    # _up_self_update  # Disabled locally to prevent overwriting fixes

    local npm_pkgs=("@google/gemini-cli" "@openai/codex" "opencode-ai" "@charmland/crush" "@qwen-code/qwen-code" "cline" "@bitwarden/cli" "@github/copilot" "@playwright/cli" "trello-cli")
    local installed_npm=()
    declare -A old_vers

    echo "Checking current versions..."

    for p in "${npm_pkgs[@]}"; do
        local version=$(npm list -g "$p" --depth=0 2>/dev/null | grep "$p" | rev | cut -d@ -f1 | rev || echo "")
        if [ -n "$version" ] && [[ "$version" != *"empty"* ]]; then
            installed_npm+=("$p")
            old_vers["npm:$p"]="$version"
        fi
    done

    if command -v gog >/dev/null 2>&1; then
        old_vers["gog"]=$(gog version | head -1 | awk "{print \$2}")
    fi

    if command -v claude >/dev/null 2>&1; then
        old_vers["claude"]=$(claude --version 2>/dev/null | head -1 || echo "N/A")
    fi

    if command -v bw >/dev/null 2>&1; then
        old_vers["bw"]=$(bw --version 2>/dev/null | head -1 || echo "N/A")
    fi

    if command -v multica >/dev/null 2>&1; then
        old_vers["multica"]=$(multica version | head -1 | awk "{print \$2}")
    fi

    if command -v dsh >/dev/null 2>&1; then
        old_vers["dsh"]=$(_dsh_version)
    fi

    echo "Fetching apt upgrade info..."
    sudo apt update > /dev/null
    local apt_upgradable=$(apt list --upgradable 2>/dev/null | grep "/")

    echo "Starting system and package updates..."
    sudo apt upgrade -y

    if [ ${#installed_npm[@]} -gt 0 ]; then
        echo "Updating npm packages: ${installed_npm[*]}"
        local prefix=$(npm config get prefix)
        # Clean up any root-owned or stale temporary directories from previous sudo runs or specific package installers
        sudo rm -rf "$prefix/lib/node_modules/@google/.gemini-cli-*" \
                   "$prefix/lib/node_modules/@openai/.codex-*" \
                   "$prefix/lib/node_modules/.codex-cli-*" \
                   "$prefix/lib/node_modules/.opencode-ai-*"
        npm install -g "${installed_npm[@]}" --force
    fi

    if command -v dsh >/dev/null 2>&1; then
        _up_dsh
    fi

    if command -v gog >/dev/null 2>&1; then
        echo "Updating gogcli..."
        local temp_dir=$(mktemp -d)
        local arch="amd64"
        [ "$(uname -m)" = "aarch64" ] && arch="arm64"

        if gh release download --repo openclaw/gogcli --pattern "*linux_${arch}.tar.gz" --dir "$temp_dir"; then
            tar -xzf "$temp_dir"/*linux_${arch}.tar.gz -C "$temp_dir"
            local gog_path=$(which gog)
            sudo mv "$temp_dir/gog" "$gog_path"
            sudo chmod +x "$gog_path"
            echo "gogcli updated successfully at $gog_path"
        else
            echo "Failed to download gogcli release."
        fi
        rm -rf "$temp_dir"
    fi

    if command -v claude >/dev/null 2>&1; then
        claude upgrade 2>/dev/null || true
    fi

    if command -v copilot >/dev/null 2>&1; then
        copilot extension upgrade 2>/dev/null || true
    fi

    if command -v multica >/dev/null 2>&1; then
        echo "Updating multica..."
        sudo multica update 2>&1 || true
        local new_multica=$(multica version | head -1 | awk "{print \$2}")
        if [ "$new_multica" != "${old_vers["multica"]}" ]; then
            echo "Restarting multica daemon..."
            export XDG_RUNTIME_DIR="/run/user/$(id -u)"
            if systemctl --user restart multica-daemon; then
                sleep 2
                if systemctl --user is-active --quiet multica-daemon; then
                    echo "Multica daemon restarted successfully."
                else
                    echo "WARNING: multica daemon failed to come back up after restart." >&2
                fi
            else
                echo "WARNING: multica daemon restart failed." >&2
            fi
        else
            echo "Multica already up to date; daemon restart skipped."
        fi
    fi

    echo -e "\n--- Update Report ---"
    printf "%-30s | %-15s -> %-15s\n" "Package" "Old" "New"
    echo "------------------------------------------------------------------------"

    if [ -n "$apt_upgradable" ]; then
        while read -r line; do
            local pkg_name=$(echo "$line" | cut -d/ -f1)
            local old_v=$(echo "$line" | awk "{print \$6}" | tr -d "[]")
            local new_v=$(echo "$line" | awk "{print \$2}")
            printf "%-30s | %-15s -> %-15s\n" "apt:$pkg_name" "$old_v" "$new_v"
        done <<< "$apt_upgradable"
    fi

    for p in "${installed_npm[@]}"; do
        local new_v=$(npm list -g "$p" --depth=0 2>/dev/null | grep "$p" | rev | cut -d@ -f1 | rev || echo "N/A")
        printf "%-30s | %-15s -> %-15s\n" "npm:$p" "${old_vers["npm:$p"]}" "$new_v"
    done

    if command -v gog >/dev/null 2>&1; then
        local new_gog=$(gog version | head -1 | awk "{print \$2}")
        printf "%-30s | %-15s -> %-15s\n" "gog" "${old_vers["gog"]}" "$new_gog"
    fi

    if command -v claude >/dev/null 2>&1; then
        local new_claude=$(claude --version 2>/dev/null | head -1 || echo "N/A")
        printf "%-30s | %-15s -> %-15s\n" "claude" "${old_vers["claude"]}" "$new_claude"
    fi

    if command -v bw >/dev/null 2>&1; then
        local new_bw=$(bw --version 2>/dev/null | head -1 || echo "N/A")
        printf "%-30s | %-15s -> %-15s\n" "bw" "${old_vers["bw"]}" "$new_bw"
    fi

    if command -v multica >/dev/null 2>&1; then
        local new_multica=$(multica version | head -1 | awk "{print \$2}")
        printf "%-30s | %-15s -> %-15s\n" "multica" "${old_vers["multica"]}" "$new_multica"
    fi

    if command -v dsh >/dev/null 2>&1; then
        local new_dsh=$(_dsh_version)
        printf "%-30s | %-15s -> %-15s\n" "dsh" "${old_vers["dsh"]}" "$new_dsh"
    fi
}
