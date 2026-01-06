# memvid-cli

Command-line interface for memvid memory operations. All output is JSON for easy integration with MCP servers and scripts.

## Build

```bash
cargo build --release
```

Binary will be at `target/release/memvid` (or `memvid.exe` on Windows).

## Commands

### create

Create a new memory file with full-text search enabled.

```bash
memvid create /path/to/memory.mv2
```

Output:
```json
{"success":true,"path":"/path/to/memory.mv2","message":"Memory file created"}
```

### put

Store content in memory. Auto-creates file if needed.

```bash
# With inline content
memvid put /path/to/memory.mv2 --content "Rust is great" --uri "mv2://topics/rust" --title "Rust" -t programming

# From stdin
echo "Content here" | memvid put /path/to/memory.mv2 --uri "mv2://notes/idea"
```

Options:
- `--content`: Content to store (reads from stdin if not provided)
- `--uri`: Hierarchical URI (e.g., `mv2://topics/rust`)
- `--title`: Title for the content
- `-t, --tag`: Tags (can be repeated)

Output:
```json
{"success":true,"frame_id":42,"message":"Content stored and committed"}
```

### search

Full-text search with optional URI scope filtering.

```bash
memvid search /path/to/memory.mv2 "programming languages"
memvid search /path/to/memory.mv2 "systems" --scope "mv2://topics/"
```

Options:
- `--scope`: URI prefix filter
- `--limit`: Maximum results (default: 10)
- `--snippet-chars`: Context characters (default: 200)

Output:
```json
{
  "query": "programming",
  "total_hits": 1,
  "elapsed_ms": 5,
  "hits": [{
    "frame_id": 42,
    "uri": "mv2://topics/rust",
    "title": "Rust",
    "snippet": "Rust is a systems programming...",
    "score": 1.84
  }]
}
```

### timeline

Browse memory chronologically.

```bash
memvid timeline /path/to/memory.mv2
memvid timeline /path/to/memory.mv2 --limit 5 --since 1704067200
```

Options:
- `--limit`: Maximum entries (default: 20)
- `--since`: Unix timestamp - entries after this time
- `--until`: Unix timestamp - entries before this time
- `--reverse`: Newest first (default: true)

Output:
```json
{
  "total": 2,
  "entries": [{
    "frame_id": 42,
    "timestamp": 1704153600,
    "uri": "mv2://topics/rust",
    "preview": "Rust is a systems programming..."
  }]
}
```

### stats

Get memory file statistics.

```bash
memvid stats /path/to/memory.mv2
```

Output:
```json
{
  "path": "/path/to/memory.mv2",
  "frame_count": 10,
  "active_frame_count": 10,
  "size_bytes": 79768,
  "has_lex_index": true,
  "has_vec_index": false
}
```

## Error Handling

On error, commands return non-zero exit code and JSON error:

```json
{"error":"File already exists: /path/to/memory.mv2"}
```

## Integration

The JSON output makes it easy to integrate with:
- MCP servers (memvid-mcp)
- Shell scripts (with jq)
- Other programming languages

Example with jq:
```bash
memvid search memory.mv2 "rust" | jq '.hits[].title'
```

## License

Apache-2.0
