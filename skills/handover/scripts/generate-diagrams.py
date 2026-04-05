#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""
generate-diagrams.py — emit Mermaid diagram blocks from a HANDOFF yaml file.

Usage:
    uv run generate-diagrams.py --handoff <path-to-HANDOFF.*.yaml> [--diagram <name>]

Diagrams:
    dependency   — inter-item dependency graph (gated: items must have deps)
    burn         — pie chart of item status distribution (gate: ≥3 items)
    velocity     — session timeline from log entries (gate: ≥2 log entries)
    hotspots     — bar chart of most-touched files (gate: ≥3 items with files, ≥3 distinct files)
    blocked      — blocker cascade chain (gated: blocked items must exist)

Output: Mermaid fenced blocks printed to stdout, separated by blank lines.
"""

import argparse
import re
import sys
from pathlib import Path

import yaml


def parse_handoff_yaml(text: str) -> dict:
    return yaml.safe_load(text) or {}


# ---------------------------------------------------------------------------
# Dependency inference
# ---------------------------------------------------------------------------

DEPENDS_ON_RE = re.compile(
    r"[Dd]epends on (minibox-\d+|#\d+)",
    re.IGNORECASE,
)
ISSUE_NUM_RE = re.compile(r"#(\d+)")


def infer_dependencies(items: list[dict]) -> dict[str, list[str]]:
    """
    Returns {item_id: [dep_id, ...]} by scanning:
    1. explicit `depends_on` field (list of item IDs)
    2. extra[].note text for "Depends on minibox-N" or "Depends on #N"
    3. extra[].blocker note text
    """
    # Build issue-number → item-id index
    issue_to_id: dict[str, str] = {}
    for item in items:
        desc = item.get("description", "")
        title = item.get("title", "")
        m = ISSUE_NUM_RE.search(title + " " + desc)
        if m:
            issue_to_id[m.group(1)] = item["id"]

    deps: dict[str, list[str]] = {}
    for item in items:
        item_id = item["id"]
        found: list[str] = list(item.get("depends_on", []))

        extras = item.get("extra", [])
        if isinstance(extras, list):
            for ex in extras:
                if not isinstance(ex, dict):
                    continue
                note = ex.get("note", "")
                for m in DEPENDS_ON_RE.finditer(note):
                    ref = m.group(1)
                    if ref.startswith("minibox-"):
                        if ref not in found:
                            found.append(ref)
                    elif ref.startswith("#"):
                        num = ref[1:]
                        resolved = issue_to_id.get(num)
                        if resolved and resolved not in found:
                            found.append(resolved)

        if found:
            deps[item_id] = found

    return deps


# ---------------------------------------------------------------------------
# File path helpers
# ---------------------------------------------------------------------------

def _file_display_name(path: str, all_paths: list[str]) -> str:
    """
    Return the shortest suffix of path that is unique among all_paths.
    Falls back to full path if no unique suffix ≤4 components exists.
    """
    parts = Path(path).parts
    for n in range(1, len(parts) + 1):
        candidate = "/".join(parts[-n:])
        if sum(1 for p in all_paths if "/".join(Path(p).parts[-n:]) == candidate) == 1:
            return candidate
    return path


# ---------------------------------------------------------------------------
# Label helpers
# ---------------------------------------------------------------------------

def abbrev(title: str, max_words: int = 3) -> str:
    """Abbreviate a title to max_words words, strip unsafe Mermaid chars."""
    # Remove parentheses content
    title = re.sub(r"\s*\(.*?\)", "", title)
    # Remove feat:/fix:/chore: prefixes
    title = re.sub(r"^(feat|fix|chore|docs|refactor|test)\s*[:/]\s*", "", title, flags=re.I)
    # Remove issue refs
    title = re.sub(r"#\d+", "", title).strip()
    # Trim to max_words
    words = title.split()[:max_words]
    return " ".join(words)


def node_id(item_id: str) -> str:
    return item_id.replace("-", "_")


# ---------------------------------------------------------------------------
# Diagram 1: Dependency graph
# ---------------------------------------------------------------------------

def diagram_dependency(items: list[dict], deps: dict[str, list[str]]) -> str:
    id_to_item = {it["id"]: it for it in items}
    lines = ["```mermaid", "flowchart TD"]

    # Nodes — only emit items that have deps or are depended upon
    in_graph = set(deps.keys())
    for dep_list in deps.values():
        in_graph.update(dep_list)

    for item in items:
        iid = item["id"]
        if iid not in in_graph:
            continue
        label = abbrev(item.get("title", iid))
        status = item.get("status", "open")
        if status == "blocked":
            lines.append(f"  {node_id(iid)}[\"{label}\"]:::blocked")
        elif status == "done":
            lines.append(f"  {node_id(iid)}(\"{label}\"):::done")
        else:
            lines.append(f"  {node_id(iid)}[\"{label}\"]")

    lines.append("")
    lines.append("  classDef blocked fill:#e67e22,color:#fff")
    lines.append("  classDef done fill:#27ae60,color:#fff")

    lines.append("")

    # Edges
    for iid, dep_list in deps.items():
        for dep in dep_list:
            if dep in id_to_item:
                lines.append(f"  {node_id(dep)} --> {node_id(iid)}")

    lines.append("```")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diagram 2: Work burn (pie)
# ---------------------------------------------------------------------------

def diagram_burn(items: list[dict]) -> str:
    """Pie chart of item status counts. Gate: ≥3 items."""
    if len(items) < 3:
        return ""

    counts: dict[str, int] = {}
    for item in items:
        status = item.get("status", "open")
        counts[status] = counts.get(status, 0) + 1

    lines = ["```mermaid", "pie title Work Distribution"]
    for status in ("done", "open", "blocked", "parked"):
        n = counts.get(status, 0)
        if n:
            lines.append(f'  "{status}" : {n}')
    lines.append("```")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diagram 3: Session velocity (timeline)
# ---------------------------------------------------------------------------

def diagram_velocity(log: list[dict], items: list[dict] | None = None) -> str:
    """Timeline of session stats per date. Gate: ≥2 log entries."""
    if len(log) < 2:
        return ""

    # Build completed-per-date index from items
    completed_by_date: dict[str, int] = {}
    for item in (items or []):
        date = str(item.get("completed", ""))
        if date:
            completed_by_date[date] = completed_by_date.get(date, 0) + 1

    # Group entries by date, count sessions and commits
    by_date: dict[str, dict] = {}
    for entry in log:
        date = str(entry.get("date", "unknown"))
        rec = by_date.setdefault(date, {"sessions": 0, "commits": 0})
        rec["sessions"] += 1
        commits = entry.get("commits") or []
        real = [c for c in commits if c and not str(c).startswith("(")]
        rec["commits"] += len(real)

    lines = ["```mermaid", "timeline"]
    for date in sorted(by_date.keys()):
        rec = by_date[date]
        lines.append(f"  {date}")
        lines.append(f"    : {rec['sessions']} session{'s' if rec['sessions'] != 1 else ''}")
        if rec["commits"]:
            lines.append(f"    : {rec['commits']} commit{'s' if rec['commits'] != 1 else ''}")
        done = completed_by_date.get(date, 0)
        if done:
            lines.append(f"    : {done} item{'s' if done != 1 else ''} done")
    lines.append("```")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diagram 4: File hotspots (bar)
# ---------------------------------------------------------------------------

def diagram_file_hotspots(items: list[dict], top_n: int = 8) -> str:
    """Bar chart of most-referenced files. Gate: ≥3 items with files, ≥3 distinct files."""
    all_paths: list[str] = []
    for item in items:
        files = item.get("files") or []
        if isinstance(files, list):
            all_paths.extend(files)

    items_with_files = sum(1 for it in items if it.get("files"))
    if items_with_files < 3:
        return ""

    distinct = set(all_paths)
    if len(distinct) < 3:
        return ""

    # Count item references per file (not raw path occurrences)
    file_item_count: dict[str, int] = {}
    for item in items:
        files = item.get("files") or []
        if not isinstance(files, list):
            continue
        for f in set(files):  # dedupe per item
            file_item_count[f] = file_item_count.get(f, 0) + 1

    top = sorted(file_item_count.items(), key=lambda x: -x[1])[:top_n]
    paths = [p for p, _ in top]
    counts = [c for _, c in top]

    labels = [_file_display_name(p, list(file_item_count.keys())) for p in paths]
    x_axis = ", ".join(f'"{l}"' for l in labels)
    max_count = max(counts) if counts else 1

    lines = [
        "```mermaid",
        "xychart-beta",
        '  title "File Hotspots"',
        f"  x-axis [{x_axis}]",
        f"  y-axis \"Items\" 0 --> {max_count}",
        f"  bar {counts}",
        "```",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diagram 4: Blocked chain
# ---------------------------------------------------------------------------

def diagram_blocked_chain(items: list[dict], deps: dict[str, list[str]]) -> str:
    id_to_item = {it["id"]: it for it in items}

    # Find all items in blocked chains
    blocked_ids = {it["id"] for it in items if it.get("status") == "blocked"}
    # Also include items that are depended upon by blocked items
    chain_ids: set[str] = set(blocked_ids)
    for iid in blocked_ids:
        for dep in deps.get(iid, []):
            chain_ids.add(dep)
    # Root blockers: status==blocked AND has extra[].type=="blocker" AND no
    # explicit depends_on pointing to another item (blocked by external cause,
    # not by another work item).
    root_blockers: set[str] = set()
    for item in items:
        if item.get("status") != "blocked":
            continue
        has_external_blocker = any(
            isinstance(ex, dict) and ex.get("type") == "blocker"
            for ex in (item.get("extra") or [])
        )
        if not has_external_blocker:
            continue
        # Only a root blocker if it has no dep pointing to another item in deps
        if item["id"] not in deps:
            root_blockers.add(item["id"])

    chain_ids |= root_blockers

    if not chain_ids:
        return ""

    lines = ["```mermaid", "flowchart TD"]

    for iid in sorted(chain_ids):
        item = id_to_item.get(iid, {})
        label = abbrev(item.get("title", iid))
        status = item.get("status", "open")
        if iid in root_blockers and status == "blocked":
            # Root external blocker (e.g. Apple OS bug)
            lines.append(f"  {node_id(iid)}[\"{label}\"]:::root_blocker")
        elif status == "blocked":
            lines.append(f"  {node_id(iid)}[\"{label}\"]:::blocked")
        else:
            # Open items that are prerequisites
            lines.append(f"  {node_id(iid)}[\"{label}\"]:::pending")

    lines.append("")
    # Explicit dep edges: dep must be completed before iid
    for iid in sorted(chain_ids):
        for dep in deps.get(iid, []):
            if dep in chain_ids:
                lines.append(f"  {node_id(dep)} --> {node_id(iid)}")

    # Root blockers gate all blocked items that have no explicit dep chain
    # (i.e. items blocked by an external issue rather than another item)
    for iid in sorted(blocked_ids):
        if iid in root_blockers:
            continue
        # already has an explicit dep path — skip dotted line
        has_dep = any(dep in chain_ids for dep in deps.get(iid, []))
        if not has_dep:
            for rb in root_blockers:
                lines.append(f"  {node_id(rb)} -.-> {node_id(iid)}")

    lines.append("")
    lines.append("  classDef root_blocker fill:#c0392b,color:#fff")
    lines.append("  classDef blocked fill:#e67e22,color:#fff")
    lines.append("  classDef pending fill:#2980b9,color:#fff")
    lines.append("```")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ALL_DIAGRAMS = ["dependency", "burn", "velocity", "hotspots", "blocked"]


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Mermaid diagrams from HANDOFF yaml")
    parser.add_argument("--handoff", required=True, help="Path to HANDOFF.*.yaml")
    parser.add_argument(
        "--diagram",
        choices=ALL_DIAGRAMS + ["all"],
        default="all",
        help="Which diagram to emit (default: all)",
    )
    args = parser.parse_args()

    path = Path(args.handoff)
    if not path.exists():
        print(f"error: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    text = path.read_text()
    data = parse_handoff_yaml(text)
    items = data.get("items", [])
    if not items:
        print("error: no items found in HANDOFF file", file=sys.stderr)
        sys.exit(1)

    log = data.get("log", [])
    deps = infer_dependencies(items)
    diagrams_to_run = ALL_DIAGRAMS if args.diagram == "all" else [args.diagram]

    outputs = []
    for name in diagrams_to_run:
        if name == "dependency":
            out = diagram_dependency(items, deps)
        elif name == "burn":
            out = diagram_burn(items)
        elif name == "velocity":
            out = diagram_velocity(log, items)
        elif name == "hotspots":
            out = diagram_file_hotspots(items)
        elif name == "blocked":
            out = diagram_blocked_chain(items, deps)
        else:
            continue
        if out:
            outputs.append(f"### {name.capitalize()}\n\n{out}")

    print("\n\n".join(outputs))


if __name__ == "__main__":
    main()
