#!/usr/bin/env bash
set -euo pipefail

MUTED='\033[0;2m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${MUTED}NITC Wiki MCP — Quick Setup${NC}"
echo ""

# 1. Install opencode if not present
if ! command -v opencode &>/dev/null; then
  echo "Installing opencode..."
  curl -fsSL https://opencode.ai/install | bash
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
mkdir -p "$CONFIG_DIR"

# 2. Create wiki config
WIKI_CONFIG="$CONFIG_DIR/wiki-mcp-config.json"
if [ ! -f "$WIKI_CONFIG" ]; then
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
  echo -e "  ${GREEN}✓${NC} Created wiki config at $WIKI_CONFIG"
fi

# 3. Add MCP server to opencode config
OPENCODE_CONFIG="$CONFIG_DIR/opencode.json"
if [ ! -f "$OPENCODE_CONFIG" ]; then
  echo '{ "$schema": "https://opencode.ai/config.json" }' > "$OPENCODE_CONFIG"
fi

# Use node to safely merge the MCP entry into the config
node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$OPENCODE_CONFIG', 'utf8'));
cfg.mcp = cfg.mcp || {};
cfg.mcp['wiki.fosscell.org'] = {
  type: 'local',
  command: ['npx', '-y', '@professional-wiki/mediawiki-mcp-server@0.10.0'],
  enabled: true,
  environment: {
    CONFIG: '$WIKI_CONFIG'
  }
};
fs.writeFileSync('$OPENCODE_CONFIG', JSON.stringify(cfg, null, 2));
" 2>/dev/null

echo -e "  ${GREEN}✓${NC} Added wiki-mcp to opencode config"

# 4. Verify
if command -v opencode &>/dev/null; then
  VER=$(opencode --version 2>/dev/null || echo "installed")
  echo -e "  ${GREEN}✓${NC} opencode $VER"
fi

echo ""
echo -e "${GREEN}Done!${NC} Just run ${MUTED}opencode${NC} and start asking about the NITC wiki."
echo "To edit pages, add your bot password to: $WIKI_CONFIG"
echo ""
