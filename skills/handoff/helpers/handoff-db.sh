#!/bin/sh
# handoff-db.sh — SQLite CRUD for HANDOFF items. Full replacement for sync-sqlite.sh.
#
# Requires: sqlite3, yq (https://github.com/mikefarah/yq v4+)
#
# Commands:
#   handoff-db.sh init
#   handoff-db.sh upsert --project <p> --handoff <path>
#   handoff-db.sh query  --project <p>
#   handoff-db.sh complete --project <p> --id <id>
#   handoff-db.sh status --project <p> --id <id> --status <s>
#
# Exit codes:
#   0  success
#   1  usage error
#   2  missing required tool (sqlite3 or yq)
#   3  file not found

set -eu

DB="${HOME}/.local/share/atelier/handoff.db"

die() { echo "error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Parse command
# ---------------------------------------------------------------------------

[ $# -ge 1 ] || die "usage: handoff-db.sh <command> [options]"
CMD="$1"; shift

# ---------------------------------------------------------------------------
# Prereqs
# ---------------------------------------------------------------------------

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not on PATH — skipping" >&2; exit 2; }

if [ "$CMD" = "upsert" ]; then
    command -v yq >/dev/null 2>&1 || { echo "yq not on PATH — skipping" >&2; exit 2; }
fi

# ---------------------------------------------------------------------------
# Init (idempotent)
# ---------------------------------------------------------------------------

_init_db() {
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
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

case "$CMD" in

    init)
        _init_db
        echo "db initialized: $DB"
        ;;

    upsert)
        PROJECT=''
        HANDOFF_PATH=''
        while [ $# -gt 0 ]; do
            case "$1" in
                --project) PROJECT="$2";      shift 2 ;;
                --handoff) HANDOFF_PATH="$2"; shift 2 ;;
                *) die "unknown argument: $1" ;;
            esac
        done
        [ -n "$PROJECT" ]      || die "--project is required"
        [ -n "$HANDOFF_PATH" ] || die "--handoff is required"
        [ -f "$HANDOFF_PATH" ] || { echo "error: file not found: $HANDOFF_PATH" >&2; exit 3; }

        _init_db
        TODAY=$(date +%Y-%m-%d)
        COUNT=$(yq '.items | length' "$HANDOFF_PATH")

        if [ "$COUNT" -eq 0 ]; then
            echo "no items found in $HANDOFF_PATH — nothing to sync" >&2
            exit 0
        fi

        synced=0
        i=0
        while [ "$i" -lt "$COUNT" ]; do
            id=$(        yq ".items[$i].id"        "$HANDOFF_PATH")
            name=$(      yq ".items[$i].name"      "$HANDOFF_PATH")
            priority=$(  yq ".items[$i].priority"  "$HANDOFF_PATH")
            status=$(    yq ".items[$i].status"    "$HANDOFF_PATH")
            completed=$( yq ".items[$i].completed" "$HANDOFF_PATH")

            [ "$name"      = "null" ] && name=''
            [ "$priority"  = "null" ] && priority=''
            [ "$status"    = "null" ] && status=''
            [ "$completed" = "null" ] && completed=''

            sqlite3 "$DB" \
                "INSERT INTO items (project, id, name, priority, status, completed, updated)
                 VALUES ('${PROJECT}', '${id}', '${name}', '${priority}', '${status}',
                         '${completed}', '${TODAY}')
                 ON CONFLICT(project, id) DO UPDATE SET
                     status=excluded.status,
                     completed=excluded.completed,
                     updated=excluded.updated;"

            synced=$(( synced + 1 ))
            i=$(( i + 1 ))
        done
        echo "synced ${synced} item(s) for project '${PROJECT}'"
        ;;

    query)
        PROJECT=''
        while [ $# -gt 0 ]; do
            case "$1" in
                --project) PROJECT="$2"; shift 2 ;;
                *) die "unknown argument: $1" ;;
            esac
        done
        [ -n "$PROJECT" ] || die "--project is required"
        _init_db
        sqlite3 "$DB" \
            "SELECT id, priority, status, coalesce(completed,''), updated
             FROM items
             WHERE project = '${PROJECT}'
             ORDER BY priority, id;"
        ;;

    complete)
        PROJECT=''
        ITEM_ID=''
        while [ $# -gt 0 ]; do
            case "$1" in
                --project) PROJECT="$2";  shift 2 ;;
                --id)      ITEM_ID="$2";  shift 2 ;;
                *) die "unknown argument: $1" ;;
            esac
        done
        [ -n "$PROJECT" ]  || die "--project is required"
        [ -n "$ITEM_ID" ]  || die "--id is required"
        _init_db
        TODAY=$(date +%Y-%m-%d)
        sqlite3 "$DB" \
            "UPDATE items SET status='done', completed='${TODAY}', updated='${TODAY}'
             WHERE project='${PROJECT}' AND id='${ITEM_ID}';"
        echo "marked done: ${PROJECT}/${ITEM_ID}"
        ;;

    status)
        PROJECT=''
        ITEM_ID=''
        NEW_STATUS=''
        while [ $# -gt 0 ]; do
            case "$1" in
                --project) PROJECT="$2";    shift 2 ;;
                --id)      ITEM_ID="$2";    shift 2 ;;
                --status)  NEW_STATUS="$2"; shift 2 ;;
                *) die "unknown argument: $1" ;;
            esac
        done
        [ -n "$PROJECT" ]    || die "--project is required"
        [ -n "$ITEM_ID" ]    || die "--id is required"
        [ -n "$NEW_STATUS" ] || die "--status is required"
        _init_db
        TODAY=$(date +%Y-%m-%d)
        sqlite3 "$DB" \
            "UPDATE items SET status='${NEW_STATUS}', updated='${TODAY}'
             WHERE project='${PROJECT}' AND id='${ITEM_ID}';"
        echo "status updated: ${PROJECT}/${ITEM_ID} → ${NEW_STATUS}"
        ;;

    *)
        die "unknown command: $CMD (init|upsert|query|complete|status)"
        ;;
esac
