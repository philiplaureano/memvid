# Memvid MCP - Agent Instructions

Drop this into your CLAUDE.md, AGENTS.md, or system prompt.

---

## Core Directive

You have persistent memory via memvid MCP. Use it proactively. Don't wait for "remember this" - recognize when to store and recall.

---

## Tools Available

| Tool | Purpose |
|------|---------|
| `memory_remember` | Store knowledge with title, content, tags, URI |
| `memory_recall` | Search memory by query, optional scope filter |
| `memory_list` | Browse recent entries chronologically |
| `memory_stats` | Check memory file status |

---

## When to Store

**Store immediately after**:
- Solving a non-trivial problem (the solution, not the struggle)
- Learning a user preference ("I prefer X over Y")
- Discovering a pattern ("This codebase uses X convention")
- Completing a significant task (what was done, key decisions)
- Encountering a gotcha ("X fails silently when Y")

**Store format**:
```
Title: [Concise description]
Content: [Distilled insight, not transcript]
Tags: [domain, topic, type]
URI: mv2://[category]/[subcategory]
```

**Example**:
```
Title: API rate limit workaround
Content: Use exponential backoff starting at 100ms. Max 5 retries. The /search endpoint has stricter limits (10/min) than /get (100/min).
Tags: ["api", "rate-limiting", "backend"]
URI: mv2://backend/api-patterns
```

---

## When to Recall

**Recall at session start**:
```
memory_list(limit=10)
```
Scan recent context. Prime yourself with what's been happening.

**Recall before answering domain questions**:
```
memory_recall(query="[relevant keywords]")
```
Check if you already know something about this topic.

**Recall when context seems missing**:
If the user references something you don't have context for, search memory before asking them to repeat.

---

## What to Store (and What Not To)

| Store | Don't Store |
|-------|-------------|
| Distilled insights | Raw conversation transcripts |
| Working solutions | Failed attempts |
| User preferences | Temporary decisions |
| Reusable patterns | One-off commands |
| Key decisions + rationale | Every micro-decision |
| Gotchas and warnings | Obvious facts |

**Compression principle**: Store what you'd want to know in 6 months, not what happened in the last 6 minutes.

---

## URI Hierarchy

Use consistent URIs for organization:

```
mv2://preferences/[topic]     - User preferences
mv2://solutions/[domain]      - Working solutions
mv2://patterns/[type]         - Reusable patterns
mv2://gotchas/[area]          - Warnings and pitfalls
mv2://projects/[name]         - Project-specific knowledge
mv2://decisions/[topic]       - Key decisions with rationale
```

---

## Proactive Behaviors

### After solving a problem:
```
[Complete solution]

Storing this solution for future reference...
memory_remember(
  title="[Problem] solution",
  content="[Distilled solution]",
  tags=["relevant", "tags"],
  uri="mv2://solutions/[domain]"
)
```

### After learning a preference:
```
Noted. Storing your preference...
memory_remember(
  title="Preference: [topic]",
  content="User prefers [X] over [Y] because [reason if given]",
  tags=["preference"],
  uri="mv2://preferences/[topic]"
)
```

### At conversation start:
```
memory_list(limit=5)
[Silently review recent context]
[Continue conversation with context-awareness]
```

### When asked about something potentially stored:
```
memory_recall(query="[topic keywords]")
[If found]: Based on our previous work...
[If not found]: I don't have prior context on this. [Proceed normally]
```

---

## Anti-Patterns

- Storing every message (noise, not signal)
- Waiting for explicit "remember this" (be proactive)
- Storing raw transcripts (distill first)
- Forgetting to recall at session start (context is free)
- Using inconsistent URIs (breaks organization)
- Storing without tags (hurts searchability)

---

## Quick Reference

```
# Store insight
memory_remember(title="...", content="...", tags=[...], uri="mv2://...")

# Search memory
memory_recall(query="keywords", scope="mv2://optional/filter")

# Browse recent
memory_list(limit=10)

# Check status
memory_stats()
```

---

**Bottom line**: Memory is cheap. Forgetting is expensive. When in doubt, store it. When answering, check memory first.
