#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""
generate-diagrams.py — emit four Mermaid diagram blocks from a HANDOFF yaml file.

Usage:
    python3 generate-diagrams.py --handoff <path-to-HANDOFF.*.yaml> [--diagram <name>]

Diagrams:
    dependency   — inter-item dependency graph (inferred from extra[].note + blocked status)
    sprint       — sprint/phase roadmap (explicit sprint field, or keyword inference)
    coverage     — crate coverage heatmap (derived from files arrays)
    blocked      — VZ / blocker cascade chain

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
# Sprint inference
# ---------------------------------------------------------------------------

SPRINT_KEYWORDS: list[tuple[str, list[str]]] = [
    ("Sprint 1 Core", ["exec into running", "named containers (#", "log capture", "auth", "handler coverage"]),
    ("Sprint 2 Linux", ["linux", "tier 3", "adapter isolation", "lifecycle failure"]),
    ("Sprint 3 Maestro", ["pty", "stdio piping", "container networking", "veth", "bridge", "maestro phase 3"]),
    ("Sprint 4 OCI", ["shared oci", "oci image-pulling", "minibox-oci"]),
    ("Sprint 5 VZ", ["vz", "vsock", "virtiofs", "virtualization.framework", "minibox-agent"]),
    ("Infra", ["ci", "license", "serial", "dagu", "dashbox", "bench"]),
]


def infer_sprint(item: dict) -> str:
    if "sprint" in item:
        return item["sprint"]
    text = (item.get("title", "") + " " + item.get("description", "")).lower()
    for sprint_name, keywords in SPRINT_KEYWORDS:
        if any(kw in text for kw in keywords):
            return sprint_name
    return "Backlog"


# ---------------------------------------------------------------------------
# Crate extraction
# ---------------------------------------------------------------------------

CRATE_FROM_PATH_RE = re.compile(r"crates/([^/]+)/")
KNOWN_CRATES = [
    "mbx", "minibox-core", "daemonbox", "miniboxd", "minibox-cli",
    "minibox-client", "macbox", "winbox", "minibox-llm", "minibox-secrets",
    "minibox-macros", "minibox-bench", "dashbox", "mbxctl", "xtask", "dockerbox",
]


def extract_crates(items: list[dict]) -> dict[str, list[str]]:
    """Returns {crate: [item_id, ...]} from files arrays."""
    crate_items: dict[str, list[str]] = {}
    for item in items:
        files = item.get("files", [])
        if not isinstance(files, list):
            continue
        seen: set[str] = set()
        for f in files:
            m = CRATE_FROM_PATH_RE.search(f)
            crate = m.group(1) if m else "root"
            if crate not in seen:
                seen.add(crate)
                crate_items.setdefault(crate, []).append(item["id"])
    return crate_items


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
# Diagram 2: Sprint roadmap
# ---------------------------------------------------------------------------

def diagram_sprint(items: list[dict]) -> str:
    sprint_map: dict[str, list[dict]] = {}
    for item in items:
        sprint = infer_sprint(item)
        sprint_map.setdefault(sprint, []).append(item)

    lines = ["```mermaid", "flowchart LR"]

    sprint_order = [s for s, _ in SPRINT_KEYWORDS]
    sprint_order.append("Backlog")

    prev_sprint = None
    for sprint in sprint_order:
        if sprint not in sprint_map:
            continue
        sprint_items = sprint_map[sprint]
        sg_id = sprint.replace(" ", "_")
        lines.append(f"  subgraph {sg_id}[\"{sprint}\"]")
        for item in sprint_items:
            iid = item["id"]
            label = abbrev(item.get("title", iid))
            status = item.get("status", "open")
            if status == "done":
                lines.append(f"    {node_id(iid)}(\"{label}\"):::done")
            elif status == "blocked":
                lines.append(f"    {node_id(iid)}[\"{label}\"]:::blocked")
            else:
                lines.append(f"    {node_id(iid)}[\"{label}\"]")
        lines.append("  end")
        if prev_sprint:
            prev_id = prev_sprint.replace(" ", "_")
            lines.append(f"  {prev_id} --> {sg_id}")
        prev_sprint = sprint

    lines.append("")
    lines.append("  classDef done fill:#27ae60,color:#fff")
    lines.append("  classDef blocked fill:#e67e22,color:#fff")
    lines.append("```")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Diagram 3: Crate coverage heatmap
# ---------------------------------------------------------------------------

def diagram_coverage(items: list[dict]) -> str:
    crate_items = extract_crates(items)
    if not crate_items:
        return ""

    # Count open vs done items per crate
    id_to_item = {it["id"]: it for it in items}

    lines = ["```mermaid", "quadrantChart"]
    lines.append("  title Crate Work Distribution")
    lines.append("  x-axis Few Items --> Many Items")
    lines.append("  y-axis All Done --> Active Work")

    max_count = max(len(v) for v in crate_items.values()) or 1

    for crate, item_ids in sorted(crate_items.items(), key=lambda x: -len(x[1])):
        total = len(item_ids)
        open_count = sum(
            1 for iid in item_ids
            if id_to_item.get(iid, {}).get("status", "open") not in ("done", "parked")
        )
        x = round(min(total / max_count, 1.0) * 0.8 + 0.1, 2)
        y = round((open_count / total) * 0.8 + 0.1, 2) if total else 0.1
        label = crate[:20]  # quadrantChart labels can be longer
        lines.append(f"  {label}: [{x}, {y}]")

    lines.append("```")
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

ALL_DIAGRAMS = ["dependency", "sprint", "coverage", "blocked"]


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

    deps = infer_dependencies(items)
    diagrams_to_run = ALL_DIAGRAMS if args.diagram == "all" else [args.diagram]

    outputs = []
    for name in diagrams_to_run:
        if name == "dependency":
            out = diagram_dependency(items, deps)
        elif name == "sprint":
            out = diagram_sprint(items)
        elif name == "coverage":
            out = diagram_coverage(items)
        elif name == "blocked":
            out = diagram_blocked_chain(items, deps)
        else:
            continue
        if out:
            outputs.append(f"### {name.capitalize()}\n\n{out}")

    print("\n\n".join(outputs))


if __name__ == "__main__":
    main()
