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
#   4  schema validation error

# Valid item statuses per schema.md
VALID_STATUSES="open done parked blocked pending-validation closed"

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
        NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        COUNT=$(yq '.items | length' "$HANDOFF_PATH")

        if [ "$COUNT" -eq 0 ]; then
            echo "no items found in $HANDOFF_PATH — nothing to sync" >&2
            exit 0
        fi

        # Validate log entries: date must be ISO 8601 with time, commits must be {sha,branch} objects
        LOG_COUNT=$(yq '.log | length' "$HANDOFF_PATH" 2>/dev/null || echo 0)
        log_warnings=0
        j=0
        while [ "$j" -lt "$LOG_COUNT" ]; do
            log_date=$(yq ".log[$j].date" "$HANDOFF_PATH")
            session=$(  yq ".log[$j].session" "$HANDOFF_PATH")
            # Bare date check: YYYY-MM-DD with no time component
            case "$log_date" in
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                    echo "warning: log[$j].date '$log_date' is a bare date — use ISO 8601 datetime (YYYY-MM-DDTHH:MM:SSZ)" >&2
                    log_warnings=$(( log_warnings + 1 ))
                    ;;
            esac
            if [ "$session" = "null" ] || [ -z "$session" ]; then
                echo "warning: log[$j] is missing required 'session' field" >&2
                log_warnings=$(( log_warnings + 1 ))
            fi
            # Check for bare commit hashes (scalar strings, not objects)
            commit_count=$(yq ".log[$j].commits | length" "$HANDOFF_PATH" 2>/dev/null || echo 0)
            c=0
            while [ "$c" -lt "$commit_count" ]; do
                sha=$(yq ".log[$j].commits[$c].sha" "$HANDOFF_PATH" 2>/dev/null || echo "null")
                if [ "$sha" = "null" ]; then
                    raw=$(yq ".log[$j].commits[$c]" "$HANDOFF_PATH")
                    echo "warning: log[$j].commits[$c] '$raw' is a bare hash — use {sha: <hash>, branch: <branch>}" >&2
                    log_warnings=$(( log_warnings + 1 ))
                fi
                c=$(( c + 1 ))
            done
            j=$(( j + 1 ))
        done
        [ "$log_warnings" -gt 0 ] && echo "warning: $log_warnings schema issue(s) found in log — see schema.md" >&2

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

            # Validate status
            status_valid=0
            for vs in $VALID_STATUSES; do
                [ "$status" = "$vs" ] && status_valid=1 && break
            done
            if [ "$status_valid" -eq 0 ] && [ -n "$status" ]; then
                echo "warning: item '$id' has unknown status '$status' (valid: $VALID_STATUSES)" >&2
            fi

            sqlite3 "$DB" \
                "INSERT INTO items (project, id, name, priority, status, completed, updated)
                 VALUES ('${PROJECT}', '${id}', '${name}', '${priority}', '${status}',
                         '${completed}', '${NOW}')
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
        NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        sqlite3 "$DB" \
            "UPDATE items SET status='done', completed='${NOW}', updated='${NOW}'
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
        # Validate status
        status_valid=0
        for vs in $VALID_STATUSES; do
            [ "$NEW_STATUS" = "$vs" ] && status_valid=1 && break
        done
        [ "$status_valid" -eq 0 ] && die "unknown status '$NEW_STATUS' (valid: $VALID_STATUSES)"
        _init_db
        NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        sqlite3 "$DB" \
            "UPDATE items SET status='${NEW_STATUS}', updated='${NOW}'
             WHERE project='${PROJECT}' AND id='${ITEM_ID}';"
        echo "status updated: ${PROJECT}/${ITEM_ID} → ${NEW_STATUS}"
        ;;

    *)
        die "unknown command: $CMD (init|upsert|query|complete|status)"
        ;;
esac
