#!/usr/bin/env bash
# sync-sqlite.sh — upsert HANDOFF items into the local SQLite handoff database.
#
# Requires: sqlite3, yq (https://github.com/mikefarah/yq v4+)
#
# Usage:
#   sync-sqlite.sh --project <name> --handoff <path-to-HANDOFF.*.yaml>
#   sync-sqlite.sh --project <name> --query   (print all items for project)
#
# Exit codes:
#   0  success
#   1  usage error
#   2  required tool not on PATH (sqlite3 or yq)
#   3  handoff file not found

set -euo pipefail

DB="${HOME}/.local/share/atelier/handoff.db"

die() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

MODE=upsert
PROJECT=''
HANDOFF_PATH=''

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)  PROJECT="$2";       shift 2 ;;
        --handoff)  HANDOFF_PATH="$2";  shift 2 ;;
        --query)    MODE=query;          shift   ;;
        *)          die "unknown argument: $1" ;;
    esac
done

[[ -n "$PROJECT" ]] || die "--project is required"

# ---------------------------------------------------------------------------
# Prereqs
# ---------------------------------------------------------------------------

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not on PATH — skipping sync" >&2; exit 2; }
command -v yq      >/dev/null 2>&1 || { echo "yq not on PATH — skipping sync" >&2; exit 2; }

mkdir -p "$(dirname "$DB")"

sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS items (
  project   TEXT NOT NULL,
  id        TEXT NOT NULL,
  name      TEXT,
  priority  TEXT,
  status    TEXT,
  completed TEXT,
  updated   TEXT,
  PRIMARY KEY (project, id)
);"

# ---------------------------------------------------------------------------
# Query mode
# ---------------------------------------------------------------------------

if [[ "$MODE" == "query" ]]; then
    sqlite3 "$DB" \
        "SELECT id, priority, status, coalesce(completed,''), updated
         FROM items
         WHERE project = '${PROJECT}'
         ORDER BY priority, id;"
    exit 0
fi

# ---------------------------------------------------------------------------
# Upsert mode
# ---------------------------------------------------------------------------

[[ -n "$HANDOFF_PATH" ]] || die "--handoff is required for upsert mode"
[[ -f "$HANDOFF_PATH" ]] || die "file not found: $HANDOFF_PATH"

TODAY=$(date +%Y-%m-%d)
COUNT=$(yq '.items | length' "$HANDOFF_PATH")

if [[ "$COUNT" -eq 0 ]]; then
    echo "no items found in $HANDOFF_PATH — nothing to sync" >&2
    exit 0
fi

synced=0
for i in $(seq 0 $(( COUNT - 1 ))); do
    id=$(        yq ".items[$i].id"        "$HANDOFF_PATH")
    name=$(      yq ".items[$i].name"      "$HANDOFF_PATH")
    priority=$(  yq ".items[$i].priority"  "$HANDOFF_PATH")
    status=$(    yq ".items[$i].status"    "$HANDOFF_PATH")
    completed=$( yq ".items[$i].completed" "$HANDOFF_PATH")

    # yq returns "null" for missing fields — normalise to empty string
    [[ "$name"      == "null" ]] && name=''
    [[ "$priority"  == "null" ]] && priority=''
    [[ "$status"    == "null" ]] && status=''
    [[ "$completed" == "null" ]] && completed=''

    sqlite3 "$DB" \
        "INSERT INTO items (project, id, name, priority, status, completed, updated)
         VALUES ('${PROJECT}', '${id}', '${name}', '${priority}', '${status}', '${completed}', '${TODAY}')
         ON CONFLICT(project, id) DO UPDATE SET
             status=excluded.status,
             completed=excluded.completed,
             updated=excluded.updated;"

    synced=$(( synced + 1 ))
done

echo "synced ${synced} item(s) for project '${PROJECT}'"
