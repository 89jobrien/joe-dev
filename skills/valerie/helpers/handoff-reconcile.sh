#!/bin/sh
# handoff-reconcile.sh — reconcile HANDOFF items with the configured doob backend.
#
# Commands:
#   handoff-reconcile.sh sync  [--handoff <path>] [--project <name>]
#   handoff-reconcile.sh audit [--handoff <path>] [--project <name>]
#
# Exit codes:
#   0  success / fully reconciled
#   1  usage error or audit found missing/closed items
#   2  missing required tool
#   3  handoff file not found

set -eu

die() {
    echo "error: $*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "$1 not on PATH — skipping" >&2
        exit 2
    }
}

MODE=sync
HANDOFF_PATH=''
PROJECT=''

if [ $# -gt 0 ]; then
    case "$1" in
        sync|audit)
            MODE="$1"
            shift
            ;;
    esac
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --handoff)
            HANDOFF_PATH="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

require_cmd doob
require_cmd yq

if [ -z "$HANDOFF_PATH" ]; then
    if command -v handoff-detect >/dev/null 2>&1; then
        HANDOFF_PATH=$(handoff-detect) || {
            status=$?
            [ "$status" -eq 2 ] && exit 3
            exit "$status"
        }
    else
        die "--handoff is required when handoff-detect is unavailable"
    fi
fi

[ -f "$HANDOFF_PATH" ] || exit 3

if [ -z "$PROJECT" ]; then
    PROJECT=$(yq -r '.project // ""' "$HANDOFF_PATH")
fi

if [ -z "$PROJECT" ] && command -v handoff-detect >/dev/null 2>&1; then
    PROJECT=$(handoff-detect --project)
fi

[ -n "$PROJECT" ] || die "could not determine project"

TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/handoff-reconcile.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

fetch_titles() {
    status="$1"
    txt_path="$TMPDIR/${status}.txt"

    if ! doob todo list -p "$PROJECT" --status "$status" --json \
        | yq -p=json -r '.todos[]?.content // ""' 2>/dev/null \
        | sed '/^$/d' >"$txt_path"
    then
        : >"$txt_path"
    fi
}

contains_line() {
    needle="$1"
    file="$2"
    [ -f "$file" ] && grep -Fqx "$needle" "$file"
}

contains_any_title() {
    title="$1"
    blocked_title="$2"
    shift 2

    for file in "$@"; do
        if contains_line "$title" "$file" || contains_line "$blocked_title" "$file"; then
            return 0
        fi
    done

    return 1
}

append_list() {
    value="$1"
    file="$2"

    if [ -n "$value" ]; then
        printf '%s\n' "$value" >>"$file"
    fi
}

map_priority() {
    case "$1" in
        P0) echo 5 ;;
        P1) echo 4 ;;
        P2) echo 3 ;;
        *)  echo 1 ;;
    esac
}

todo_content_from_name() {
    slug="$1"

    if [ -z "$slug" ] || [ "$slug" = "null" ]; then
        return 1
    fi

    printf '%s' "$slug" | tr '-' ' ' | awk '
        {
            $1 = toupper(substr($1, 1, 1)) substr($1, 2)
            print
        }
    '
}

fetch_titles pending
fetch_titles in_progress
fetch_titles completed
fetch_titles cancelled

pending_titles="$TMPDIR/pending.txt"
in_progress_titles="$TMPDIR/in_progress.txt"
completed_titles="$TMPDIR/completed.txt"
cancelled_titles="$TMPDIR/cancelled.txt"

active_titles="$TMPDIR/active.txt"
cat "$pending_titles" "$in_progress_titles" 2>/dev/null | sort -u >"$active_titles" || :

open_count=$(yq '.items // [] | map(select(.status == "open" or .status == "blocked")) | length' "$HANDOFF_PATH")

captured_count=0
created_count=0
not_captured_file="$TMPDIR/not-captured.txt"
closed_file="$TMPDIR/closed-upstream.txt"
handoff_titles_file="$TMPDIR/handoff-titles.txt"
: >"$not_captured_file"
: >"$closed_file"
: >"$handoff_titles_file"

i=0
while [ "$i" -lt "$open_count" ]; do
    name=$(yq -r ".items // [] | map(select(.status == \"open\" or .status == \"blocked\")) | .[$i].name // \"\"" "$HANDOFF_PATH")
    title=$(yq -r ".items // [] | map(select(.status == \"open\" or .status == \"blocked\")) | .[$i].title" "$HANDOFF_PATH")
    status=$(yq -r ".items // [] | map(select(.status == \"open\" or .status == \"blocked\")) | .[$i].status" "$HANDOFF_PATH")
    priority=$(yq -r ".items // [] | map(select(.status == \"open\" or .status == \"blocked\")) | .[$i].priority" "$HANDOFF_PATH")

    content_title="$title"
    if content_from_name=$(todo_content_from_name "$name"); then
        content_title="$content_from_name"
    fi

    blocked_title="${title} [BLOCKED]"
    blocked_content="${content_title} [BLOCKED]"
    desired_title="$content_title"
    [ "$status" = "blocked" ] && desired_title="$blocked_content"

    append_list "$title" "$handoff_titles_file"
    append_list "$blocked_title" "$handoff_titles_file"
    append_list "$content_title" "$handoff_titles_file"
    append_list "$blocked_content" "$handoff_titles_file"

    if contains_any_title "$title" "$blocked_title" "$pending_titles" "$in_progress_titles" \
        || contains_any_title "$content_title" "$blocked_content" "$pending_titles" "$in_progress_titles"; then
        captured_count=$((captured_count + 1))
        i=$((i + 1))
        continue
    fi

    if contains_any_title "$title" "$blocked_title" "$completed_titles" "$cancelled_titles" \
        || contains_any_title "$content_title" "$blocked_content" "$completed_titles" "$cancelled_titles"; then
        append_list "$desired_title" "$closed_file"
        i=$((i + 1))
        continue
    fi

    if [ "$MODE" = "sync" ]; then
        mapped_priority=$(map_priority "$priority")
        doob todo add "$desired_title" --priority "$mapped_priority" -p "$PROJECT" -t "handoff,$PROJECT" >/dev/null
        append_list "$desired_title" "$active_titles"
        captured_count=$((captured_count + 1))
        created_count=$((created_count + 1))
    else
        append_list "$desired_title" "$not_captured_file"
    fi

    i=$((i + 1))
done

orphaned_file="$TMPDIR/orphaned.txt"
: >"$orphaned_file"
if [ -s "$active_titles" ]; then
    while IFS= read -r todo_title; do
        [ -n "$todo_title" ] || continue
        if ! contains_line "$todo_title" "$handoff_titles_file"; then
            append_list "$todo_title" "$orphaned_file"
        fi
    done <"$active_titles"
fi

not_captured_count=$(wc -l <"$not_captured_file" | tr -d ' ')
closed_count=$(wc -l <"$closed_file" | tr -d ' ')
orphaned_count=$(wc -l <"$orphaned_file" | tr -d ' ')

echo "Reconciliation — $PROJECT"
echo "==========================="
echo "Captured (HANDOFF→doob):  $captured_count items"
[ "$MODE" = "sync" ] && echo "Created this run:         $created_count items"
echo "Not captured:             $not_captured_count items"
echo "Orphaned todos:           $orphaned_count items"
echo "Closed upstream:          $closed_count items"

print_list() {
    label="$1"
    file="$2"

    if [ -s "$file" ]; then
        echo "$label"
        sed 's/^/- /' "$file"
    fi
}

print_list "Missing items:" "$not_captured_file"
print_list "Orphaned todos:" "$orphaned_file"
print_list "Closed upstream:" "$closed_file"

if [ "$MODE" = "audit" ] && { [ "$not_captured_count" -gt 0 ] || [ "$closed_count" -gt 0 ]; }; then
    exit 1
fi
