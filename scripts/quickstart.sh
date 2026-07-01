#!/usr/bin/env bash
set -euo pipefail

MUTED='\033[0;2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${MUTED}NITC Wiki MCP — Quick Setup${NC}"
echo ""

# Detect platform
OS="$(uname -s)"
case "$OS" in
  Darwin)   PLATFORM="macos" ;;
  Linux)    PLATFORM="linux" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
  *)        echo "Unsupported OS: $OS"; exit 1 ;;
esac

# Determine config directory
if [ "$PLATFORM" = "windows" ]; then
  CONFIG_DIR="${APPDATA}/opencode"
else
  CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
fi

# 1. Install opencode if not present
if ! command -v opencode &>/dev/null; then
  echo "  Installing opencode..."
  if [ "$PLATFORM" = "windows" ]; then
    powershell -Command "iwr https://opencode.ai/install.ps1 | iex"
  else
    curl -fsSL https://opencode.ai/install | bash
  fi
  echo ""
fi

mkdir -p "$CONFIG_DIR"

# 2. Create wiki config
WIKI_CONFIG="$CONFIG_DIR/wiki-mcp-config.json"
cat > "$WIKI_CONFIG" << 'CONFIG'
{
  "defaultWiki": "wiki.fosscell.org",
  "wikis": {
    "wiki.fosscell.org": {
      "server": "https://wiki.fosscell.org",
      "articlepath": "",
      "scriptpath": "",
      "username": null,
      "password": null,
      "private": false
    }
  }
}
CONFIG
echo -e "  ${GREEN}✓${NC} Created wiki config"

# 3. Create opencode config with wiki-mcp (removes any existing config)
OPENCODE_CONFIG="$CONFIG_DIR/opencode.json"
WARN_BACKUP=""
if [ -f "$OPENCODE_CONFIG" ]; then
  WARN_BACKUP=" (backed up as opencode.json.bak)"
  cp "$OPENCODE_CONFIG" "$OPENCODE_CONFIG.bak" 2>/dev/null || true
fi
cat > "$OPENCODE_CONFIG" << CONFIG
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "wiki.fosscell.org": {
      "type": "local",
      "command": ["npx", "-y", "@professional-wiki/mediawiki-mcp-server@0.10.0"],
      "enabled": true,
      "environment": {
        "CONFIG": "${WIKI_CONFIG}",
        "MCP_TRUSTED_HOSTS": "wiki.fosscell.org"
      }
    }
  }
}
CONFIG
echo -e "  ${GREEN}✓${NC} Created opencode config with wiki-mcp${WARN_BACKUP}"

# 4. Verify node is available (needed for npx)
if ! command -v node &>/dev/null; then
  echo -e "  ${YELLOW}⚠${NC} Node.js is required. Install from https://nodejs.org"
fi

# 5. Verify opencode
if command -v opencode &>/dev/null; then
  echo -e "  ${GREEN}✓${NC} opencode $(opencode --version 2>/dev/null || echo 'installed')"
fi

echo ""

# 6. Prompt for bot credentials
echo -e "${MUTED}To edit wiki pages, you need a bot password from${NC}"
echo -e "${MUTED}  https://wiki.fosscell.org/Special:BotPasswords${NC}"
echo ""
read -r -p "Set up bot credentials now? (y/n): " SETUP_BOT
if [ "$SETUP_BOT" = "y" ] || [ "$SETUP_BOT" = "Y" ]; then
  read -r -p "  Bot username: " BOT_USER
  echo -n "  Bot password (typing hidden): "
  BOT_PASS=""
  # Read password silently — works in both bash 3/4 and zsh
  if [ -n "${BASH_VERSION-}" ] && [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    stty -echo 2>/dev/null
    trap 'stty echo 2>/dev/null' EXIT INT TERM HUP
    read -r BOT_PASS
    stty echo 2>/dev/null
    trap - EXIT INT TERM HUP
  else
    read -rs BOT_PASS
  fi
  echo ""

  # Write credentials into the wiki config (via env var — safe from ps leak)
  export WIKI_BOT_USER="$BOT_USER"
  export WIKI_BOT_PASS="$BOT_PASS"
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, os
path = '$WIKI_CONFIG'
with open(path) as f: cfg = json.load(f)
cfg['wikis']['wiki.fosscell.org']['username'] = os.environ['WIKI_BOT_USER']
cfg['wikis']['wiki.fosscell.org']['password'] = os.environ['WIKI_BOT_PASS']
with open(path, 'w') as f: json.dump(cfg, f, indent=2)
" && echo -e "  ${GREEN}✓${NC} Bot credentials saved"
  elif command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$WIKI_CONFIG', 'utf8'));
cfg.wikis['wiki.fosscell.org'].username = process.env.WIKI_BOT_USER;
cfg.wikis['wiki.fosscell.org'].password = process.env.WIKI_BOT_PASS;
fs.writeFileSync('$WIKI_CONFIG', JSON.stringify(cfg, null, 2));
" && echo -e "  ${GREEN}✓${NC} Bot credentials saved"
  else
    echo -e "  ${YELLOW}⚠${NC} Could not save (python3/node required)."
    echo -e "  Add them manually to: ${MUTED}$WIKI_CONFIG${NC}"
  fi
  unset WIKI_BOT_USER WIKI_BOT_PASS
fi

echo ""
echo -e "${GREEN}Done!${NC} Run ${MUTED}opencode${NC} and start asking about the NITC wiki."
echo -e "See ${MUTED}WIKI_MCP.md${NC} for a step-by-step explanation of how the MCP server works."
