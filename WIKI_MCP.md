# NITC Wiki MCP — Step-by-Step

This fork of opencode bundles a pre-configured [MediaWiki MCP Server](https://github.com/ProfessionalWiki/MediaWiki-MCP-Server) for `wiki.fosscell.org`. It lets you read, search, and edit the NITC wiki directly through opencode agents.

---

## How It Works

opencode supports MCP (Model Context Protocol) servers — external processes that expose tools the AI agent can call. The MediaWiki MCP Server wraps the MediaWiki API and exposes 26+ tools.

```
┌──────────────┐   stdio/JSON-RPC   ┌────────────────────┐   HTTPS   ┌──────────────────┐
│  opencode     │ ◄────────────────► │ mediawiki-mcp-     │ ◄───────► │ wiki.fosscell.org │
│  (AI agent)   │   tools/list       │ server (npx)       │           │ (MediaWiki API)   │
│               │   tools/call       │                    │           │                   │
└──────────────┘                    └────────────────────┘           └──────────────────┘
```

**Flow:**
1. opencode starts and launches the MediaWiki MCP server as a child process
2. The MCP server probes the wiki for extensions (SMW, Cargo)
3. The MCP server announces available tools back to opencode
4. When you ask a wiki question, opencode calls the matching tool
5. The MCP server authenticates with your bot password and makes the API call
6. Results are returned to opencode as structured text

---

## Configuration Files

### `~/.config/opencode/opencode.json`

The top-level config that registers the MCP server:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "wiki.fosscell.org": {
      "type": "local",
      "command": ["npx", "-y", "@professional-wiki/mediawiki-mcp-server@0.10.0"],
      "enabled": true,
      "environment": {
        "CONFIG": "/Users/you/.config/opencode/wiki-mcp-config.json",
        "MCP_TRUSTED_HOSTS": "wiki.fosscell.org",
        "NODE_OPTIONS": "--dns-result-order=ipv4first"
      }
    }
  }
}
```

| Field | Purpose |
|---|---|
| `command` | Launches the MCP server via `npx` (no global install needed) |
| `CONFIG` | Path to wiki connection settings |
| `MCP_TRUSTED_HOSTS` | Bypasses the SSRF guard (needed if DNS resolves to a NAT64 IPv6 address) |
| `NODE_OPTIONS` | Forces Node.js to prefer IPv4 over IPv6 (avoids slow NAT64 gateways) |

### `~/.config/opencode/wiki-mcp-config.json`

The wiki connection settings:

```json
{
  "defaultWiki": "wiki.fosscell.org",
  "wikis": {
    "wiki.fosscell.org": {
      "server": "https://wiki.fosscell.org",
      "articlepath": "",
      "scriptpath": "",
      "username": "YourBot@bot",
      "password": "your-bot-password",
      "private": false
    }
  }
}
```

| Field | Value | Why |
|---|---|---|
| `server` | `https://wiki.fosscell.org` | Base URL of the wiki |
| `articlepath` | `""` (empty) | Pages at root: `/Main_Page` not `/wiki/Main_Page` |
| `scriptpath` | `""` (empty) | API at `/api.php` not `/w/api.php` |
| `username` | `BotUsername@bot` | Bot password username (format: `Username@bot`) |
| `password` | secret | Bot password from wiki's Special:BotPasswords |

---

## Authentication (Bot Passwords)

Write tools (create, edit, delete pages) require authentication.

1. Go to `wiki.fosscell.org` → Special:BotPasswords
2. Create a new bot with **at minimum** these grants:
   - `Edit existing pages`
   - `Create, edit, and move pages`
   - `Delete pages, revisions, and log entries`
3. Copy the generated username (format: `YourUser@botname`) and password
4. Add them to `wiki-mcp-config.json`

The MCP server logs `Login successful: username@https://wiki.fosscell.org/api.php` on each authenticated call.

---

## Available Tools

### Read Tools (no auth needed)

| Tool | Description |
|---|---|
| `get-page` | Fetch a page's wikitext or HTML |
| `get-pages` | Batch fetch up to 50 pages |
| `search-page` | Full-text search across titles and content |
| `search-page-by-prefix` | Title autocomplete (up to 500 results) |
| `get-site-info` | Wiki metadata (version, namespaces, extensions) |
| `get-page-history` | Revision history |
| `get-recent-changes` | Recent wiki activity |
| `compare-pages` | Diff two page versions |
| `parse-wikitext` | Preview wikitext without saving |
| `get-file` | File metadata and download URLs |
| `get-category-members` | List pages in a category |
| `get-links-here` | Find backlinks and transclusions |

### Write Tools (require bot password)

| Tool | Permission needed |
|---|---|
| `create-page` | Create, edit, and move pages |
| `update-page` | Edit existing pages |
| `move-page` | Create, edit, and move pages |
| `delete-page` | Delete pages, revisions, and log entries |
| `undelete-page` | Delete pages, revisions, and log entries |
| `upload-file` | Upload new files |
| `update-file` | Upload, replace, and move files |

### Extension Tools (auto-detected)

If the wiki has the Cargo or Semantic MediaWiki extension, additional tools appear (`cargo-query`, `smw-query`, etc.).

---

## Step-by-Step Test

After running the quickstart script, verify the MCP server works:

```bash
# 1. Check the MCP server starts
CONFIG=~/.config/opencode/wiki-mcp-config.json \
MCP_TRUSTED_HOSTS=wiki.fosscell.org \
NODE_OPTIONS=--dns-result-order=ipv4first \
npx -y @professional-wiki/mediawiki-mcp-server@0.10.0 --help
# You should see startup logs (plaintext credential warnings are normal)

# 2. Test a read tool (send JSON-RPC via stdin)
echo '{"method":"tools/call","jsonrpc":"2.0","id":1,"params":{"name":"search-page","arguments":{"wiki":"wiki.fosscell.org","query":"FOSSMeet","limit":2}}}' | \
CONFIG=~/.config/opencode/wiki-mcp-config.json \
MCP_TRUSTED_HOSTS=wiki.fosscell.org \
NODE_OPTIONS=--dns-result-order=ipv4first \
npx -y @professional-wiki/mediawiki-mcp-server@0.10.0 2>/dev/null | grep -o '"text":"[^"]*"' | head -3
# Returns page titles and snippets

# 3. Run opencode and ask about the wiki
opencode
# Then ask: "What pages are on the NITC wiki?"
```

First call takes ~10s (cold start: npx downloads + server startup + NAT64 connection). Subsequent calls are faster.

---

## Troubleshooting

### NAT64 / Slow Connections

If your DNS resolves `wiki.fosscell.org` to a `64:ff9b::` NAT64 address, connections may be slow (10-30s per call).

- `NODE_OPTIONS=--dns-result-order=ipv4first` forces Node.js to prefer IPv4
- `MCP_TRUSTED_HOSTS=wiki.fosscell.org` bypasses the SSRF guard that blocks non-public addresses
- For the fastest fix, add to `/etc/hosts`: `68.233.115.209 wiki.fosscell.org`

### "Extension probe failed" Warning

This shows at startup but is harmless — it means the server couldn't detect Cargo/SMW extensions. All core read/write tools still work.

### "Tool not found"

The `whoami` tool was added in v0.13.0. This fork pins v0.10.0 for stability. Upgrade by changing the version in `opencode.json`.

### "Request failed with status code 404"

Check `scriptpath` in `wiki-mcp-config.json`. For this wiki it must be `""` (empty string), not `/w`.

### File uploads

`upload-file` and `update-file` need `uploadDirs` configured — see the [MCP server docs](https://github.com/ProfessionalWiki/MediaWiki-MCP-Server/blob/main/docs/configuration.md#upload-directories).

---

## Files in This Fork

| File | Purpose |
|---|---|
| `scripts/quickstart.sh` | One-liner install script |
| `packages/opencode/src/config/config.ts` | Default config generation (creates MCP entry on first run) |
| `WIKI_MCP.md` | This guide |
