---
name: using-gkg
description: >
  Use when needing a structured knowledge graph of a codebase for exploration or search. gkg
  index a repo, then use gkg search or gkg context to find definitions, usages, and
  relationships.
allowed-tools: Read, Bash, Glob, Grep
---

# using-gkg — Knowledge Graph Exploration

gkg is a knowledge graph tool for codebases that indexes symbols, definitions, and
relationships, then enables fast search and contextual lookup. Use it when you need to
understand a codebase structure, find definitions, trace usages, or explore cross-module
relationships.

## What gkg Is

gkg builds a semantic index of a codebase — symbols (functions, types, variables, imports),
their definitions, usages, and relationships. Unlike `grep` or `rg`, which search text,
gkg understands code structure.

**When to use gkg:**
- Finding all usages of a symbol across a large codebase
- Tracing the definition chain (where is `MyType` defined? what implements it?)
- Understanding cross-module relationships
- Exploring unfamiliar codebases quickly

**When to use grep/rg instead:**
- One-off text search in a few files
- Pattern matching on specific keywords or strings
- No preprocessing time available (gkg indexing takes seconds)

## Step 1 — Index a Repo

Index a codebase to build the knowledge graph:

```bash
gkg index /path/to/repo
```

This scans the repo, builds a symbol index, and writes it to `.gkg/` (in the repo root or
a temporary location). Indexing is fast (typically <10 seconds for moderate repos).

**Example:**

```bash
gkg index /Users/joe/dev/minibox
```

After indexing, you can search the same repo without re-indexing.

## Step 2 — Search Symbols

Search for a symbol, function, type, or pattern:

```bash
gkg search "<query>"
```

Returns all matches with file paths and line numbers.

**Examples:**

```bash
# Find all definitions and usages of the function `deploy`
gkg search "deploy"

# Search for a type definition
gkg search "type Agent struct"

# Find imports of a module
gkg search "import mbx"
```

## Step 3 — Get Context on a Symbol

Look up the definition and usage context for a specific symbol:

```bash
gkg context <symbol>
```

Returns the symbol definition, declaration location, and nearby code context.

**Example:**

```bash
gkg context Agent
```

## MCP Access via mcpipe

gkg is accessible via MCP (through the `mcpipe` local proxy). The SSE endpoint is:

```
http://localhost:27495/mcp/sse
```

This allows Claude Code to query the knowledge graph programmatically without running shell
commands. The endpoint supports:

- `gkg.index` — trigger indexing
- `gkg.search` — search for symbols
- `gkg.context` — get definition context

To use via MCP, you do not need to run gkg manually; the plugin will invoke it through the
SSE endpoint.

## Workflow Example

### Scenario: Exploring the minibox codebase

1. **Index the repo:**
   ```bash
   gkg index /Users/joe/dev/minibox
   ```

2. **Search for the main Agent type:**
   ```bash
   gkg search "struct Agent"
   ```
   Output: file paths and line numbers of all Agent definitions and usages.

3. **Get context on the Agent type:**
   ```bash
   gkg context Agent
   ```
   Output: the struct definition, its fields, and usage patterns.

4. **Search for callers of a specific function:**
   ```bash
   gkg search "fn provision"
   ```
   Output: all references to the `provision` function.

## Performance & Limits

- Indexing: typically <10 seconds for repos up to ~100K lines
- Caching: index is cached locally; re-run `gkg index` to refresh
- Search: returns all matches; filter output if needed

## Troubleshooting

### gkg: command not found

Ensure gkg is installed:

```bash
which gkg
```

If not found, install via `mise`:

```bash
mise install gkg
```

### Index is stale

Re-index the repo:

```bash
rm -rf .gkg/
gkg index /path/to/repo
```

### MCP endpoint not responding

Verify mcpipe is running:

```bash
curl http://localhost:27495/mcp/sse -v
```

If not, start mcpipe as documented in the plugin configuration.

## Additional Resources

- **gkg docs:** Run `gkg --help` for CLI reference
- **mcpipe:** Local MCP proxy configuration and setup
