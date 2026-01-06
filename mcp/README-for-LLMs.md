# memvid-mcp: Memory Tools for AI Agents

This document explains how to use the memvid memory tools effectively.

## The Big Picture

You have access to a persistent memory file. Unlike conversation context that disappears when the session ends, this memory persists across sessions. Use it to:

- **Remember** insights and solutions for later
- **Recall** relevant knowledge when solving problems
- **Browse** what you've stored to build context

## The Tools

### memory_remember

**When to use:** You've learned something worth keeping. A solution, an insight, a preference, a decision.

**Good content:**
- "User prefers TypeScript over JavaScript for new projects"
- "The authentication bug was caused by missing CORS headers on /api/auth"
- "Satori uses FTT storage with Azure Blob backend"

**Bad content:**
- Entire conversations (too large, low signal)
- Temporary notes (defeats the purpose of persistence)
- Generic facts (you already know these)

**URI patterns:**
```
mv2://topics/{topic}         - Topical knowledge
mv2://projects/{project}     - Project-specific info
mv2://decisions/{id}         - Important decisions
mv2://preferences/{area}     - User preferences
```

**Example:**
```json
{
  "content": "Philip prefers British English spelling and metric units",
  "uri": "mv2://preferences/locale",
  "title": "Locale Preferences",
  "tags": ["preferences", "locale"]
}
```

### memory_recall

**When to use:** You need context about something you might have stored before.

**Search tips:**
- Use specific nouns: "authentication bug" not "the problem"
- Use `scope` to filter: `mv2://projects/satori` for Satori-specific memory
- Start with 5-10 results, increase if needed

**Example:**
```json
{
  "query": "authentication CORS",
  "scope": "mv2://projects/satori",
  "limit": 5
}
```

### memory_list

**When to use:** You want to see what's stored without searching for something specific.

**Use cases:**
- Starting a session - what's in memory?
- Building context - recent entries
- Finding things you forgot about

**Example:**
```json
{
  "limit": 10
}
```

### memory_stats

**When to use:** Checking if memory is working, seeing how much is stored.

## Patterns

### Pattern 1: Remember As You Learn

When you solve a problem or learn something useful, immediately store it:

```
User: "The bug was in the CORS config"
You: [Stores insight] [Responds to user]
```

Don't wait until the end of a session - you might forget.

### Pattern 2: Recall Before Answering

When asked about something you might have stored:

```
User: "How does Satori authentication work?"
You: [Recalls "authentication" with scope "mv2://projects/satori"]
     [Uses results to inform answer]
```

### Pattern 3: Browse for Context

At session start or when switching topics:

```
[Lists recent entries]
[Recalls relevant topics based on user's question]
[Builds context before responding]
```

### Pattern 4: Organize with URIs

Keep URIs consistent so `scope` filtering works:

```
mv2://projects/satori/architecture
mv2://projects/satori/bugs
mv2://projects/satori/decisions

Recall with scope="mv2://projects/satori" to get all Satori context
```

## Anti-Patterns

### Don't: Store Everything

Memory is for high-value information. Not every message needs storing.

### Don't: Forget to Use Scope

Without scope, you search everything. With scope, you get relevant results.

### Don't: Use Vague URIs

Bad: `mv2://stuff/thing1`
Good: `mv2://projects/memvid/api-verification`

### Don't: Skip the Title

Titles help you quickly scan memory_list results.

## Technical Notes

- Memory persists in a single `.mv2` file
- Content is indexed for full-text search (BM25)
- No vector search in default config
- All operations are atomic and crash-safe
