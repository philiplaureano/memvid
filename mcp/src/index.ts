#!/usr/bin/env node
/**
 * memvid-mcp: MCP server for memvid memory operations
 *
 * This server wraps the memvid CLI to expose memory operations as MCP tools.
 * All operations are stateless - each tool call opens the file fresh.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { spawn } from "child_process";
import * as path from "path";

// Default memory file path from environment
const DEFAULT_MEMORY_PATH = process.env.MEMVID_DEFAULT_PATH || "";

// Path to memvid CLI binary (relative to this package or from PATH)
const CLI_PATH = process.env.MEMVID_CLI_PATH || "memvid";

export interface CliResult {
  success: boolean;
  stdout: string;
  stderr: string;
}

/**
 * Execute the memvid CLI with given arguments
 */
export async function runCli(args: string[]): Promise<CliResult> {
  return new Promise((resolve) => {
    const proc = spawn(CLI_PATH, args, {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (data) => {
      stdout += data.toString();
    });

    proc.stderr.on("data", (data) => {
      stderr += data.toString();
    });

    proc.on("close", (code) => {
      resolve({
        success: code === 0,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
      });
    });

    proc.on("error", (err) => {
      resolve({
        success: false,
        stdout: "",
        stderr: err.message,
      });
    });
  });
}

/**
 * Resolve memory file path - use default if not provided
 */
export function resolvePath(inputPath?: string): string {
  if (inputPath) return inputPath;
  if (DEFAULT_MEMORY_PATH) return DEFAULT_MEMORY_PATH;
  throw new Error(
    "No memory file path provided. Set MEMVID_DEFAULT_PATH or provide 'path' parameter."
  );
}

// Tool definitions with cognitive framing
export const TOOLS = [
  {
    name: "memory_remember",
    description:
      "Store knowledge in memory. Use this to save insights, solutions, or information for later recall. Content is indexed for full-text search.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description:
            "Path to memory file (.mv2). Uses MEMVID_DEFAULT_PATH if not provided.",
        },
        content: {
          type: "string",
          description: "The knowledge to store",
        },
        uri: {
          type: "string",
          description:
            "Hierarchical identifier (e.g., mv2://topics/rust, mv2://projects/satori)",
        },
        title: {
          type: "string",
          description: "Short title for the content",
        },
        tags: {
          type: "array",
          items: { type: "string" },
          description: "Tags for categorization",
        },
      },
      required: ["content"],
    },
  },
  {
    name: "memory_recall",
    description:
      "Search memory for relevant knowledge. Returns matching content with snippets. Use scope to filter by URI prefix.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description:
            "Path to memory file (.mv2). Uses MEMVID_DEFAULT_PATH if not provided.",
        },
        query: {
          type: "string",
          description: "Search query",
        },
        scope: {
          type: "string",
          description: "URI prefix filter (e.g., mv2://topics/)",
        },
        limit: {
          type: "number",
          description: "Maximum results (default: 10)",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "memory_list",
    description:
      "Browse memory chronologically. Returns recent entries with previews. Use to see what knowledge is stored.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description:
            "Path to memory file (.mv2). Uses MEMVID_DEFAULT_PATH if not provided.",
        },
        limit: {
          type: "number",
          description: "Maximum entries (default: 20)",
        },
        since: {
          type: "number",
          description: "Unix timestamp - entries after this time",
        },
        until: {
          type: "number",
          description: "Unix timestamp - entries before this time",
        },
      },
    },
  },
  {
    name: "memory_stats",
    description:
      "Get statistics about the memory file. Shows frame count, size, and index status.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description:
            "Path to memory file (.mv2). Uses MEMVID_DEFAULT_PATH if not provided.",
        },
      },
    },
  },
  {
    name: "memory_create",
    description:
      "Create a new memory file. Only needed if starting fresh - memory_remember auto-creates if file doesn't exist.",
    inputSchema: {
      type: "object" as const,
      properties: {
        path: {
          type: "string",
          description: "Path to create the memory file (.mv2)",
        },
      },
      required: ["path"],
    },
  },
];

// Create server
const server = new Server(
  {
    name: "memvid-mcp",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List tools handler
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

// Call tool handler
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "memory_remember": {
        const memPath = resolvePath(args?.path as string | undefined);
        const cliArgs = ["put", memPath];

        if (args?.content) {
          cliArgs.push("--content", args.content as string);
        }
        if (args?.uri) {
          cliArgs.push("--uri", args.uri as string);
        }
        if (args?.title) {
          cliArgs.push("--title", args.title as string);
        }
        if (args?.tags && Array.isArray(args.tags)) {
          for (const tag of args.tags) {
            cliArgs.push("-t", tag as string);
          }
        }

        const result = await runCli(cliArgs);
        const data = JSON.parse(result.stdout);

        return {
          content: [
            {
              type: "text",
              text: result.success
                ? `Stored in frame ${data.frame_id}`
                : `Error: ${data.error || result.stderr}`,
            },
          ],
        };
      }

      case "memory_recall": {
        const memPath = resolvePath(args?.path as string | undefined);
        const cliArgs = ["search", memPath, args?.query as string];

        if (args?.scope) {
          cliArgs.push("--scope", args.scope as string);
        }
        if (args?.limit) {
          cliArgs.push("--limit", String(args.limit));
        }

        const result = await runCli(cliArgs);
        const data = JSON.parse(result.stdout);

        if (!result.success) {
          return {
            content: [
              { type: "text", text: `Error: ${data.error || result.stderr}` },
            ],
          };
        }

        // Format results for agent consumption
        let text = `Found ${data.total_hits} results for "${data.query}":\n\n`;
        for (const hit of data.hits) {
          text += `**${hit.title || hit.uri}** (frame ${hit.frame_id})\n`;
          text += `${hit.snippet}\n\n`;
        }

        return {
          content: [{ type: "text", text }],
        };
      }

      case "memory_list": {
        const memPath = resolvePath(args?.path as string | undefined);
        const cliArgs = ["timeline", memPath];

        if (args?.limit) {
          cliArgs.push("--limit", String(args.limit));
        }
        if (args?.since) {
          cliArgs.push("--since", String(args.since));
        }
        if (args?.until) {
          cliArgs.push("--until", String(args.until));
        }

        const result = await runCli(cliArgs);
        const data = JSON.parse(result.stdout);

        if (!result.success) {
          return {
            content: [
              { type: "text", text: `Error: ${data.error || result.stderr}` },
            ],
          };
        }

        // Format timeline for agent consumption
        let text = `Memory contains ${data.total} entries:\n\n`;
        for (const entry of data.entries) {
          const date = new Date(entry.timestamp * 1000).toISOString();
          text += `**${entry.uri || `frame-${entry.frame_id}`}** (${date})\n`;
          text += `${entry.preview.slice(0, 100)}...\n\n`;
        }

        return {
          content: [{ type: "text", text }],
        };
      }

      case "memory_stats": {
        const memPath = resolvePath(args?.path as string | undefined);
        const result = await runCli(["stats", memPath]);
        const data = JSON.parse(result.stdout);

        if (!result.success) {
          return {
            content: [
              { type: "text", text: `Error: ${data.error || result.stderr}` },
            ],
          };
        }

        const text =
          `Memory: ${data.path}\n` +
          `Frames: ${data.active_frame_count} active / ${data.frame_count} total\n` +
          `Size: ${(data.size_bytes / 1024).toFixed(1)} KB\n` +
          `Full-text search: ${data.has_lex_index ? "enabled" : "disabled"}\n` +
          `Vector search: ${data.has_vec_index ? "enabled" : "disabled"}`;

        return {
          content: [{ type: "text", text }],
        };
      }

      case "memory_create": {
        const memPath = args?.path as string;
        if (!memPath) {
          return {
            content: [{ type: "text", text: "Error: path is required" }],
          };
        }

        const result = await runCli(["create", memPath]);
        const data = JSON.parse(result.stdout);

        return {
          content: [
            {
              type: "text",
              text: result.success
                ? `Created memory file: ${data.path}`
                : `Error: ${data.error || result.stderr}`,
            },
          ],
        };
      }

      default:
        return {
          content: [{ type: "text", text: `Unknown tool: ${name}` }],
        };
    }
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Error: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
    };
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("memvid-mcp server started");
}

main().catch(console.error);
