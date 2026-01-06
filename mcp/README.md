# memvid-mcp

MCP (Model Context Protocol) server for memvid memory operations. Gives AI agents persistent, searchable memory through a single file.

## Installation

```bash
npm install -g memvid-mcp
```

You also need the `memvid` CLI binary. Build from source:

```bash
cd ../cli
cargo build --release
# Add target/release to PATH or set MEMVID_CLI_PATH
```

## Configuration

Add to your Claude Desktop config (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "memvid": {
      "command": "memvid-mcp",
      "env": {
        "MEMVID_DEFAULT_PATH": "/path/to/your/memory.mv2",
        "MEMVID_CLI_PATH": "/path/to/memvid"
      }
    }
  }
}
```

## Tools

### memory_remember

Store knowledge for later recall. Content is indexed for full-text search.

**Parameters:**
- `content` (required): The knowledge to store
- `uri`: Hierarchical identifier (e.g., `mv2://topics/rust`)
- `title`: Short title for the content
- `tags`: Array of tags for categorization
- `path`: Memory file path (uses `MEMVID_DEFAULT_PATH` if not provided)

**Example:**
```
"Remember that Rust's ownership model prevents memory leaks at compile time"
→ Stored in frame 42
```

### memory_recall

Search memory for relevant knowledge. Returns matching content with snippets.

**Parameters:**
- `query` (required): Search terms
- `scope`: URI prefix filter (e.g., `mv2://topics/` to search only topics)
- `limit`: Maximum results (default: 10)
- `path`: Memory file path

**Example:**
```
"What do I know about Rust ownership?"
→ Found 3 results for "Rust ownership":
  **Rust Language** (frame 42)
  Rust's ownership model prevents memory leaks...
```

### memory_list

Browse memory chronologically. Shows recent entries with previews.

**Parameters:**
- `limit`: Maximum entries (default: 20)
- `since`: Unix timestamp - entries after this time
- `until`: Unix timestamp - entries before this time
- `path`: Memory file path

**Example:**
```
"What have I stored recently?"
→ Memory contains 15 entries:
  **mv2://topics/rust** (2026-01-06T12:00:00Z)
  Rust's ownership model prevents...
```

### memory_stats

Get statistics about the memory file.

**Parameters:**
- `path`: Memory file path

**Returns:**
```
Memory: /path/to/memory.mv2
Frames: 15 active / 15 total
Size: 78.0 KB
Full-text search: enabled
Vector search: disabled
```

### memory_create

Create a new memory file. Usually not needed - `memory_remember` auto-creates.

**Parameters:**
- `path` (required): Path to create the .mv2 file

## Environment Variables

| Variable | Description |
|----------|-------------|
| `MEMVID_DEFAULT_PATH` | Default memory file if `path` not provided |
| `MEMVID_CLI_PATH` | Path to memvid CLI binary (default: `memvid` from PATH) |

## URI Convention

Use hierarchical URIs to organize knowledge:

```
mv2://topics/{topic}         # Topic-based storage
mv2://projects/{project}     # Project-specific knowledge
mv2://conversations/{id}     # Conversation context
mv2://daily/{YYYY-MM-DD}     # Daily notes
```

The `scope` parameter in `memory_recall` filters by URI prefix.

## Architecture

```
┌─────────────┐     stdio      ┌─────────────┐    subprocess    ┌─────────────┐
│  LLM Agent  │ ◄───────────► │ memvid-mcp  │ ◄──────────────► │ memvid CLI  │
│  (Claude)   │     MCP        │  (Node.js)  │      JSON        │   (Rust)    │
└─────────────┘                └─────────────┘                  └─────────────┘
                                                                       │
                                                                       ▼
                                                                ┌─────────────┐
                                                                │  .mv2 file  │
                                                                │  (memory)   │
                                                                └─────────────┘
```

## License

Apache-2.0
