# memvid-mcp Quickstart

**What**: Persistent memory for Claude Desktop, Claude Code, and GitHub Copilot CLI.
**Time**: 2 minutes.

---

## Install

**macOS/Linux**:
```bash
curl -fsSL https://raw.githubusercontent.com/philiplaureano/memvid/main/mcp/install.sh | bash
```

**Windows** (PowerShell as Administrator):
```powershell
irm https://raw.githubusercontent.com/philiplaureano/memvid/main/mcp/install.ps1 | iex
```

Done. The script:
1. Creates `~/.memvid/memory.mv2`
2. Configures all detected AI clients
3. Tells you what to do next

---

## Restart Claude Desktop

**Required**. Fully quit (not just close window), then reopen.

- macOS: Cmd+Q
- Windows: Right-click tray icon → Quit

---

## Verify

**Claude Desktop**: Look for hammer icon in the input box. Click it → memvid tools should appear.

**Claude Code**:
```bash
claude mcp list
```
Output should include `memvid`.

**Copilot CLI**:
```
/mcp show
```
Output should include `memvid`.

---

## Use It

Store something:
```
Remember this: The API key rotation happens every 90 days.
```

Recall it later:
```
What did I store about API keys?
```

List everything:
```
Show my memories
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Hammer icon missing | Restart Claude Desktop (fully quit first) |
| "memvid not found" | Run installer again, check npm is installed |
| Permission denied | Run PowerShell as Administrator (Windows) |
| Config parse error | Check JSON syntax in config file |

---

## Custom Memory Path

Default: `~/.memvid/memory.mv2`

Override:
```bash
# macOS/Linux
./install.sh --memory-path /path/to/custom.mv2

# Windows
.\install.ps1 -MemoryPath "D:\path\to\custom.mv2"
```

---

## Uninstall

**macOS/Linux**:
```bash
./install.sh --uninstall
```

**Windows**:
```powershell
.\install.ps1 -Uninstall
```

Removes memvid from all client configs. Does not delete memory file.

---

## Agent Instructions (Optional)

Want your AI to use memory proactively? Add this to your CLAUDE.md, AGENTS.md, or system prompt:

```markdown
## Memory (memvid MCP)

You have persistent memory. Use it proactively.

**Store after**: Solving problems, learning preferences, discovering patterns, encountering gotchas.
**Recall before**: Answering domain questions, when context seems missing.
**At session start**: Run `memory_list(limit=5)` to prime context.

**Store format**:
- Title: Concise description
- Content: Distilled insight (not transcript)
- Tags: [domain, topic, type]
- URI: mv2://category/subcategory

**What to store**: Solutions, preferences, patterns, decisions, warnings.
**What NOT to store**: Raw transcripts, failed attempts, obvious facts.

**Principle**: Store what you'd want to know in 6 months.
```

For comprehensive guidance, see [MEMVID_INSTRUCTIONS.md](./MEMVID_INSTRUCTIONS.md).

---

**That's it.** Memory persists across sessions. Your AI clients now remember.
