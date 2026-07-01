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
        "CONFIG": "${WIKI_CONFIG}"
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
echo -e "${GREEN}All set!${NC} Run ${MUTED}opencode${NC} and ask about the NITC wiki."
echo -e "To edit pages, add your bot password to: ${MUTED}$WIKI_CONFIG${NC}"
echo ""
