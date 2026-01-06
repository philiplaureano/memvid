//! memvid-cli: Command-line interface for memvid memory operations.
//!
//! All output is JSON for easy parsing by the MCP server wrapper.

use clap::{Parser, Subcommand};
use memvid_core::{Memvid, PutOptions, SearchRequest, TimelineQuery};
use serde::Serialize;
use std::io::{self, Read};
use std::num::NonZeroU64;
use std::path::PathBuf;

/// memvid CLI - Memory operations for AI agents
#[derive(Parser)]
#[command(name = "memvid")]
#[command(about = "CLI for memvid memory operations", version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new memory file
    Create {
        /// Path to create the .mv2 file
        path: PathBuf,
    },

    /// Store content in memory
    Put {
        /// Path to .mv2 file
        path: PathBuf,

        /// Content to store (reads from stdin if not provided)
        #[arg(long)]
        content: Option<String>,

        /// URI for hierarchical addressing (e.g., mv2://topics/rust)
        #[arg(long)]
        uri: Option<String>,

        /// Title for the content
        #[arg(long)]
        title: Option<String>,

        /// Tags (can be specified multiple times)
        #[arg(long, short = 't')]
        tag: Vec<String>,
    },

    /// Search memory content
    Search {
        /// Path to .mv2 file
        path: PathBuf,

        /// Search query
        query: String,

        /// URI prefix filter (scope)
        #[arg(long)]
        scope: Option<String>,

        /// Maximum results
        #[arg(long, default_value = "10")]
        limit: usize,

        /// Snippet characters
        #[arg(long, default_value = "200")]
        snippet_chars: usize,
    },

    /// Browse memory chronologically
    Timeline {
        /// Path to .mv2 file
        path: PathBuf,

        /// Maximum entries
        #[arg(long, default_value = "20")]
        limit: u64,

        /// Since timestamp (Unix epoch)
        #[arg(long)]
        since: Option<i64>,

        /// Until timestamp (Unix epoch)
        #[arg(long)]
        until: Option<i64>,

        /// Newest first (default: true)
        #[arg(long, default_value = "true")]
        reverse: bool,
    },

    /// Get memory statistics
    Stats {
        /// Path to .mv2 file
        path: PathBuf,
    },
}

// JSON output types

#[derive(Serialize)]
struct CreateOutput {
    success: bool,
    path: String,
    message: String,
}

#[derive(Serialize)]
struct PutOutput {
    success: bool,
    frame_id: u64,
    message: String,
}

#[derive(Serialize)]
struct SearchOutput {
    query: String,
    total_hits: usize,
    elapsed_ms: u128,
    hits: Vec<SearchHitOutput>,
}

#[derive(Serialize)]
struct SearchHitOutput {
    frame_id: u64,
    uri: String,
    title: Option<String>,
    snippet: String,
    score: Option<f32>,
}

#[derive(Serialize)]
struct TimelineOutput {
    total: usize,
    entries: Vec<TimelineEntryOutput>,
}

#[derive(Serialize)]
struct TimelineEntryOutput {
    frame_id: u64,
    timestamp: i64,
    uri: Option<String>,
    preview: String,
}

#[derive(Serialize)]
struct StatsOutput {
    path: String,
    frame_count: u64,
    active_frame_count: u64,
    size_bytes: u64,
    has_lex_index: bool,
    has_vec_index: bool,
}

#[derive(Serialize)]
struct ErrorOutput {
    error: String,
}

fn main() {
    let cli = Cli::parse();

    let result = match cli.command {
        Commands::Create { path } => cmd_create(&path),
        Commands::Put {
            path,
            content,
            uri,
            title,
            tag,
        } => cmd_put(&path, content, uri, title, tag),
        Commands::Search {
            path,
            query,
            scope,
            limit,
            snippet_chars,
        } => cmd_search(&path, &query, scope, limit, snippet_chars),
        Commands::Timeline {
            path,
            limit,
            since,
            until,
            reverse,
        } => cmd_timeline(&path, limit, since, until, reverse),
        Commands::Stats { path } => cmd_stats(&path),
    };

    match result {
        Ok(json) => println!("{json}"),
        Err(e) => {
            let error = ErrorOutput {
                error: e.to_string(),
            };
            println!("{}", serde_json::to_string(&error).unwrap());
            std::process::exit(1);
        }
    }
}

fn cmd_create(path: &PathBuf) -> Result<String, Box<dyn std::error::Error>> {
    if path.exists() {
        return Err(format!("File already exists: {}", path.display()).into());
    }

    let mut mem = Memvid::create(path)?;
    mem.enable_lex()?;
    mem.commit()?;

    let output = CreateOutput {
        success: true,
        path: path.display().to_string(),
        message: "Memory file created".to_string(),
    };
    Ok(serde_json::to_string(&output)?)
}

fn cmd_put(
    path: &PathBuf,
    content: Option<String>,
    uri: Option<String>,
    title: Option<String>,
    tags: Vec<String>,
) -> Result<String, Box<dyn std::error::Error>> {
    // Read content from stdin if not provided
    let content = match content {
        Some(c) => c,
        None => {
            let mut buf = String::new();
            io::stdin().read_to_string(&mut buf)?;
            buf
        }
    };

    if content.trim().is_empty() {
        return Err("Content cannot be empty".into());
    }

    // Open or create file
    let mut mem = if path.exists() {
        Memvid::open(path)?
    } else {
        let m = Memvid::create(path)?;
        m
    };

    // Ensure lex is enabled
    mem.enable_lex()?;

    // Build options
    let mut builder = PutOptions::builder();
    if let Some(u) = uri {
        builder = builder.uri(u);
    }
    if let Some(t) = title {
        builder = builder.title(t);
    }
    for tag in tags {
        builder = builder.push_tag(tag);
    }
    let opts = builder.build();

    // Store content
    let frame_id = mem.put_bytes_with_options(content.as_bytes(), opts)?;
    mem.commit()?;

    let output = PutOutput {
        success: true,
        frame_id,
        message: "Content stored and committed".to_string(),
    };
    Ok(serde_json::to_string(&output)?)
}

fn cmd_search(
    path: &PathBuf,
    query: &str,
    scope: Option<String>,
    limit: usize,
    snippet_chars: usize,
) -> Result<String, Box<dyn std::error::Error>> {
    let mut mem = Memvid::open(path)?;

    let request = SearchRequest {
        query: query.to_string(),
        top_k: limit,
        snippet_chars,
        uri: None,
        scope,
        cursor: None,
        as_of_frame: None,
        as_of_ts: None,
        no_sketch: false,
    };

    let response = mem.search(request)?;

    let hits: Vec<SearchHitOutput> = response
        .hits
        .into_iter()
        .map(|hit| SearchHitOutput {
            frame_id: hit.frame_id,
            uri: hit.uri,
            title: hit.title,
            snippet: hit.text,
            score: hit.score,
        })
        .collect();

    let output = SearchOutput {
        query: query.to_string(),
        total_hits: response.total_hits,
        elapsed_ms: response.elapsed_ms,
        hits,
    };
    Ok(serde_json::to_string(&output)?)
}

fn cmd_timeline(
    path: &PathBuf,
    limit: u64,
    since: Option<i64>,
    until: Option<i64>,
    reverse: bool,
) -> Result<String, Box<dyn std::error::Error>> {
    let mut mem = Memvid::open(path)?;

    let query = TimelineQuery {
        limit: NonZeroU64::new(limit),
        since,
        until,
        reverse,
        ..Default::default()
    };

    let entries = mem.timeline(query)?;

    let entries_out: Vec<TimelineEntryOutput> = entries
        .into_iter()
        .map(|e| TimelineEntryOutput {
            frame_id: e.frame_id,
            timestamp: e.timestamp,
            uri: e.uri,
            preview: e.preview,
        })
        .collect();

    let output = TimelineOutput {
        total: entries_out.len(),
        entries: entries_out,
    };
    Ok(serde_json::to_string(&output)?)
}

fn cmd_stats(path: &PathBuf) -> Result<String, Box<dyn std::error::Error>> {
    let mem = Memvid::open(path)?;
    let stats = mem.stats()?;

    let output = StatsOutput {
        path: path.display().to_string(),
        frame_count: stats.frame_count,
        active_frame_count: stats.active_frame_count,
        size_bytes: stats.size_bytes,
        has_lex_index: stats.has_lex_index,
        has_vec_index: stats.has_vec_index,
    };
    Ok(serde_json::to_string(&output)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_create_new_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.mv2");

        let result = cmd_create(&path);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: CreateOutput = serde_json::from_str(&json).unwrap();
        assert!(output.success);
        assert!(path.exists());
    }

    #[test]
    fn test_create_fails_if_exists() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("existing.mv2");

        cmd_create(&path).unwrap();

        let result = cmd_create(&path);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("already exists"));
    }

    #[test]
    fn test_put_creates_file_if_not_exists() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("new.mv2");

        let result = cmd_put(
            &path,
            Some("Test content".to_string()),
            Some("mv2://test/uri".to_string()),
            Some("Test Title".to_string()),
            vec!["tag1".to_string(), "tag2".to_string()],
        );

        assert!(result.is_ok());
        assert!(path.exists());

        let json = result.unwrap();
        let output: PutOutput = serde_json::from_str(&json).unwrap();
        assert!(output.success);
        assert!(output.frame_id > 0);
    }

    #[test]
    fn test_put_appends_to_existing_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("append.mv2");

        cmd_put(&path, Some("First content".to_string()), None, None, vec![]).unwrap();

        let result = cmd_put(&path, Some("Second content".to_string()), None, None, vec![]);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: PutOutput = serde_json::from_str(&json).unwrap();
        assert!(output.frame_id > 1);
    }

    #[test]
    fn test_put_rejects_empty_content() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("empty.mv2");

        let result = cmd_put(&path, Some("   ".to_string()), None, None, vec![]);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("empty"));
    }

    #[test]
    fn test_search_finds_content() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("search.mv2");

        cmd_put(
            &path,
            Some("Rust is a systems programming language".to_string()),
            Some("mv2://topics/rust".to_string()),
            Some("Rust Language".to_string()),
            vec!["programming".to_string()],
        )
        .unwrap();

        let result = cmd_search(&path, "systems programming", None, 10, 200);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: SearchOutput = serde_json::from_str(&json).unwrap();
        assert_eq!(output.query, "systems programming");
        assert!(output.total_hits > 0);
        assert!(!output.hits.is_empty());
        assert_eq!(output.hits[0].uri, "mv2://topics/rust");
    }

    #[test]
    fn test_search_with_scope_filter() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("scope.mv2");

        cmd_put(&path, Some("Rust programming".to_string()), Some("mv2://topics/rust".to_string()), None, vec![]).unwrap();
        cmd_put(&path, Some("Python programming".to_string()), Some("mv2://topics/python".to_string()), None, vec![]).unwrap();
        cmd_put(&path, Some("My project uses Rust".to_string()), Some("mv2://projects/myapp".to_string()), None, vec![]).unwrap();

        let result = cmd_search(&path, "programming", Some("mv2://topics/".to_string()), 10, 200);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: SearchOutput = serde_json::from_str(&json).unwrap();

        for hit in &output.hits {
            assert!(hit.uri.starts_with("mv2://topics/"));
        }
    }

    #[test]
    fn test_search_returns_empty_for_no_match() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("nomatch.mv2");

        cmd_put(&path, Some("Hello world".to_string()), None, None, vec![]).unwrap();

        let result = cmd_search(&path, "nonexistent query xyz123", None, 10, 200);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: SearchOutput = serde_json::from_str(&json).unwrap();
        assert_eq!(output.total_hits, 0);
        assert!(output.hits.is_empty());
    }

    #[test]
    fn test_timeline_returns_entries() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("timeline.mv2");

        cmd_put(&path, Some("First entry".to_string()), None, None, vec![]).unwrap();
        cmd_put(&path, Some("Second entry".to_string()), None, None, vec![]).unwrap();
        cmd_put(&path, Some("Third entry".to_string()), None, None, vec![]).unwrap();

        let result = cmd_timeline(&path, 10, None, None, true);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: TimelineOutput = serde_json::from_str(&json).unwrap();
        assert_eq!(output.total, 3);
        assert_eq!(output.entries.len(), 3);
    }

    #[test]
    fn test_timeline_respects_limit() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("limit.mv2");

        for i in 1..=5 {
            cmd_put(&path, Some(format!("Entry {}", i)), None, None, vec![]).unwrap();
        }

        let result = cmd_timeline(&path, 2, None, None, true);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: TimelineOutput = serde_json::from_str(&json).unwrap();
        assert_eq!(output.total, 2);
    }

    #[test]
    fn test_stats_returns_correct_counts() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("stats.mv2");

        cmd_create(&path).unwrap();
        cmd_put(&path, Some("Entry 1".to_string()), None, None, vec![]).unwrap();
        cmd_put(&path, Some("Entry 2".to_string()), None, None, vec![]).unwrap();

        let result = cmd_stats(&path);
        assert!(result.is_ok());

        let json = result.unwrap();
        let output: StatsOutput = serde_json::from_str(&json).unwrap();
        assert!(output.frame_count >= 2);
        assert!(output.has_lex_index);
        assert!(!output.has_vec_index);
        assert!(output.size_bytes > 0);
    }

    #[test]
    fn test_stats_fails_for_nonexistent_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("nonexistent.mv2");

        let result = cmd_stats(&path);
        assert!(result.is_err());
    }

    #[test]
    fn test_json_output_is_valid() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("json.mv2");

        let create_json = cmd_create(&path).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&create_json).is_ok());

        let put_json = cmd_put(&path, Some("Test".to_string()), None, None, vec![]).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&put_json).is_ok());

        let search_json = cmd_search(&path, "Test", None, 10, 200).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&search_json).is_ok());

        let timeline_json = cmd_timeline(&path, 10, None, None, true).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&timeline_json).is_ok());

        let stats_json = cmd_stats(&path).unwrap();
        assert!(serde_json::from_str::<serde_json::Value>(&stats_json).is_ok());
    }
}
