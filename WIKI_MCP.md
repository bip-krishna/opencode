# Wiki MCP Server — Step by Step

This fork of opencode bundles a [MediaWiki MCP Server](https://github.com/ProfessionalWiki/MediaWiki-MCP-Server) so you can ask questions about the NITC wiki (`wiki.fosscell.org`) and edit pages — all through natural language.

---

## How It Works

### 1. The MCP Protocol

[MCP (Model Context Protocol)](https://modelcontextprotocol.io) lets an AI agent (opencode) talk to external tools through a standardized interface. Think of it as a USB port for AI — plug in a server, and the agent gains new capabilities.

```
┌─────────────┐    MCP (stdio)    ┌─────────────────────────┐
│  opencode   │ ◄──────────────► │  mediawiki-mcp-server   │
│  (AI agent) │   JSON-RPC 2.0   │  (npx process)          │
└─────────────┘                   └─────────────────────────┘
                                           │
                                    MediaWiki API
                                    (HTTPS)
                                           │
                                    ┌──────┴──────┐
                                    │ wiki.fosscell.org │
                                    └─────────────┘
```

OpenCode spawns the MCP server as a child process (`npx @professional-wiki/mediawiki-mcp-server@0.10.0`). They communicate over stdin/stdout using JSON-RPC 2.0 messages.

### 2. Configuration Files

Two files control the setup:

#### `~/.config/opencode/opencode.json`
Tells opencode to launch the MCP server and passes it environment variables:

```json
{
  "mcp": {
    "wiki.fosscell.org": {
      "type": "local",
      "command": ["npx", "-y", "@professional-wiki/mediawiki-mcp-server@0.10.0"],
      "enabled": true,
      "environment": {
        "CONFIG": "/Users/me/.config/opencode/wiki-mcp-config.json",
        "MCP_TRUSTED_HOSTS": "wiki.fosscell.org"
      }
    }
  }
}
```

| Field | Purpose |
|---|---|
| `type: "local"` | Run the server as a local child process (not remote) |
| `command` | How to start the server — `npx -y` downloads & runs without prompting |
| `enabled: true` | Start the server when opencode launches |
| `environment.CONFIG` | Path to the wiki connection details |
| `environment.MCP_TRUSTED_HOSTS` | Bypasses the SSRF guard for NAT64 networks |

#### `~/.config/opencode/wiki-mcp-config.json`
Connection details for the wiki:

```json
{
  "defaultWiki": "wiki.fosscell.org",
  "wikis": {
    "wiki.fosscell.org": {
      "server": "https://wiki.fosscell.org",
      "articlepath": "",
      "scriptpath": "",
      "username": "MyBot@bot",
      "password": "…",
      "private": false
    }
  }
}
```

| Field | Purpose |
|---|---|
| `server` | Wiki base URL |
| `scriptpath` | Where MediaWiki's `api.php` lives. Empty = at root (`/api.php`) |
| `username` / `password` | Bot password for authenticated tools |
| `private: false` | Anonymous read access is allowed |

### 3. Authentication Flow

```
                  MCP Server                    MediaWiki API
                       │                             │
  1. Start server ───► │                             │
                       ├──► GET /api.php?action=query│
                       │    &meta=tokens&type=login  │──► Returns login token
                       │◄─────────────────────────── │
                       │                             │
  2. Login ───────────► ├──► POST /api.php           │
                       │    action=login              │
                       │    lgname=Bip-krishna@mcp-bot│
                       │    lgpassword=…              │
                       │    lgtoken=…                 │
                       │◄─────────────────────────── │──► Sets auth cookies
                       │                             │
  3. Tool call ───────► ├──► POST /api.php           │
  (e.g. get-page)       │    action=parse             │
                       │    page=Some_Title           │
                       │    (cookies attached)        │
                       │◄─────────────────────────── │──► Returns page content
                       │                             │
  4. Result ──────────► opencode
```

- **Read-only tools** (`get-page`, `search-page`, `get-site-info`, etc.) don't need authentication for public wikis.
- **Write tools** (`create-page`, `update-page`, etc.) require the bot to log in first using the credentials from `wiki-mcp-config.json`.
- The bot password must have the appropriate grants (e.g. `Edit existing pages` for `update-page`).

### 4. Available Tools

#### Read Tools (no auth needed)

| Tool | What it does |
|---|---|
| `get-page` | Fetch a wiki page (wikitext or HTML) |
| `get-pages` | Fetch multiple pages at once |
| `search-page` | Full-text search across the wiki |
| `search-page-by-prefix` | Title autocomplete |
| `get-page-history` | Revision history of a page |
| `get-recent-changes` | Recent wiki activity |
| `get-site-info` | Wiki metadata (version, namespaces, extensions) |
| `get-category-members` | List pages in a category |
| `get-links-here` | Pages that link to a given page |
| `get-file` | File metadata and download URLs |
| `get-revision` | Fetch a specific historical revision |
| `parse-wikitext` | Render wikitext to HTML without saving |
| `compare-pages` | Diff two versions of a page |

#### Write Tools (require bot auth)

| Tool | Required Grant |
|---|---|
| `create-page` | Create, edit, and move pages |
| `update-page` | Edit existing pages |
| `move-page` | Create, edit, and move pages |
| `delete-page` | Delete pages, revisions, and log entries |
| `undelete-page` | Delete pages, revisions, and log entries |
| `upload-file` | Upload new files |
| `upload-file-from-url` | Upload new files |
| `update-file` | Upload, replace, and move files |
| `update-file-from-url` | Upload, replace, and move files |

### 5. Startup Sequence (Detailed)

When you run `opencode`, this happens:

```
1. opencode reads ~/.config/opencode/opencode.json
2. Finds MCP server "wiki.fosscell.org" configured as type: "local"
3. Spawns: npx -y @professional-wiki/mediawiki-mcp-server@0.10.0
   with CONFIG env var pointing to wiki-mcp-config.json
   and MCP_TRUSTED_HOSTS=wiki.fosscell.org
4. npx downloads the package (first run) or uses npm cache (subsequent runs)
5. The MCP server starts and:
   a. Reads wiki-mcp-config.json
   b. Probes the wiki API for installed extensions (SMW, Cargo, etc.)
   c. Advertises its tool list to opencode over MCP
6. opencode's AI now has access to all wiki tools
7. When you ask a question, opencode calls the appropriate MCP tool
8. The MCP server translates the request into MediaWiki API calls
9. Results flow back: wiki → MCP server → opencode → you
```

### 6. Network Notes

The NITC wiki resolves to a **NAT64 IPv6 address** (`64:ff9b:...`), which the MCP server's built-in SSRF guard considers non-public. The `MCP_TRUSTED_HOSTS` environment variable exempts `wiki.fosscell.org` from this check, allowing the server to connect.

The startup probe for extensions (SMW/Cargo) may still log a warning about the NAT64 address, but this is cosmetic — all read and write tools work normally.

---

## Quick Reference

### One-liner install
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bip-krishna/opencode/dev/scripts/quickstart.sh)"
```

### Config file locations
- `~/.config/opencode/opencode.json` — MCP server registration
- `~/.config/opencode/wiki-mcp-config.json` — Wiki connection & credentials

### Restart after config changes
Press `Ctrl+R` in opencode to reload config, or restart opencode entirely.

### Verify the server is running
Ask opencode: "What tools are available on the wiki?" or "Show me the site info for wiki.fosscell.org".

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Tool not found` | Server didn't start | Check `opencode.json` syntax, restart opencode |
| `Request failed with status code 404` | Wrong `scriptpath` | Set `scriptpath: ""` in `wiki-mcp-config.json` |
| `Refusing to fetch URL resolving to non-public address` | NAT64 / IPv6 issue | Ensure `MCP_TRUSTED_HOSTS=wiki.fosscell.org` is set |
| `Invalid username or password` | Wrong bot credentials | Re-run quickstart script or edit `wiki-mcp-config.json` |
| Write tools not listed | No auth configured | Add `username` / `password` to `wiki-mcp-config.json` |
