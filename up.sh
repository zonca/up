#!/usr/bin/env bash
# up.sh — Update system packages and AI coding assistants with version reporting
# Repo: https://github.com/zonca/up
# Install: curl -o ~/.up.sh https://raw.githubusercontent.com/zonca/up/main/up.sh
#          echo 'source ~/.up.sh' >> ~/.bashrc

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

up() {
    _up_self_update

    local npm_pkgs=("@google/gemini-cli" "@openai/codex" "opencode-ai" "@charmland/crush" "@qwen-code/qwen-code" "cline" "@bitwarden/cli" "@github/copilot")
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

    echo "Fetching apt upgrade info..."
    sudo apt update > /dev/null
    local apt_upgradable=$(apt list --upgradable 2>/dev/null | grep "/")

    echo "Starting system and package updates..."
    sudo apt upgrade -y

    if [ ${#installed_npm[@]} -gt 0 ]; then
        echo "Updating npm packages: ${installed_npm[*]}"
        local prefix=$(npm config get prefix)
        sudo rm -rf "$prefix/lib/node_modules/@google/.gemini-cli-*" "$prefix/lib/node_modules/.codex-cli-*"
        sudo npm install -g "${installed_npm[@]}" --force
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
}
