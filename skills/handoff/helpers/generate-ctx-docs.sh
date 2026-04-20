#!/bin/sh
# generate-ctx-docs.sh — Write .ctx/HANDOFF.md and .ctx/HANDOVER.md from HANDOFF YAML.
#
# Usage:
#   generate-ctx-docs.sh --handoff <path> --state <path> --ctx <dir>
#
# Arguments:
#   --handoff  Path to HANDOFF.<name>.<base>.yaml
#   --state    Path to HANDOFF.<name>.<base>.state.yaml (optional; use "" to skip)
#   --ctx      Output directory (default: .ctx relative to HANDOFF file's directory)
#
# Requires: yq (https://github.com/mikefarah/yq v4+)
#
# Exit codes:
#   0  success
#   1  usage error
#   2  missing required tool
#   3  file not found

set -eu

die() { echo "error: $*" >&2; exit 1; }

HANDOFF_PATH=''
STATE_PATH=''
CTX_DIR=''

while [ $# -gt 0 ]; do
    case "$1" in
        --handoff) HANDOFF_PATH="$2"; shift 2 ;;
        --state)   STATE_PATH="$2";   shift 2 ;;
        --ctx)     CTX_DIR="$2";      shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[ -n "$HANDOFF_PATH" ] || die "--handoff is required"
[ -f "$HANDOFF_PATH" ] || die "file not found: $HANDOFF_PATH"

command -v yq >/dev/null 2>&1 || { echo "yq not on PATH — cannot generate ctx docs" >&2; exit 2; }

# Derive ctx dir from handoff file location if not specified
if [ -z "$CTX_DIR" ]; then
    CTX_DIR="$(dirname "$HANDOFF_PATH")"
fi

mkdir -p "$CTX_DIR"

# ---------------------------------------------------------------------------
# Read HANDOFF fields
# ---------------------------------------------------------------------------

project=$(yq '.project // ""'  "$HANDOFF_PATH")
updated=$(yq '.updated  // ""'  "$HANDOFF_PATH")
notes=$(  yq '.notes    // ""'  "$HANDOFF_PATH")

# State fields (optional)
branch='unknown'
build='unknown'
tests='unknown'

if [ -n "$STATE_PATH" ] && [ -f "$STATE_PATH" ]; then
    branch=$(yq '.branch // "unknown"' "$STATE_PATH")
    build=$( yq '.build  // "unknown"' "$STATE_PATH")
    tests=$( yq '.tests  // "unknown"' "$STATE_PATH")
fi

# ---------------------------------------------------------------------------
# Generate .ctx/HANDOFF.md
# ---------------------------------------------------------------------------

HANDOFF_MD="$CTX_DIR/HANDOFF.md"

{
    printf '# Handoff — %s (%s)\n\n' "$project" "$updated"
    printf '**Branch:** %s | **Build:** %s | **Tests:** %s\n' "$branch" "$build" "$tests"

    if [ -n "$notes" ] && [ "$notes" != "null" ]; then
        printf '\n%s\n' "$notes"
    fi

    printf '\n## Items\n\n'
    printf '| ID | P | Status | Title |\n'
    printf '|---|---|---|---|\n'

    # Emit open items first (sorted by priority string P0→P2), then blocked.
    # Two-pass: yq handles each filter separately and concatenates output.
    yq -r '
      (.items // []) | map(select(.status != "blocked")) | sort_by(.priority) |
      .[] |
      "| " + (.id // "-") + " | " + (.priority // "-") + " | " + (.status // "open") + " | " + (.name // "-") + " |"
    ' "$HANDOFF_PATH" 2>/dev/null || true
    yq -r '
      (.items // []) | map(select(.status == "blocked")) | sort_by(.priority) |
      .[] |
      "| " + (.id // "-") + " | " + (.priority // "-") + " | blocked | " + (.name // "-") + " |"
    ' "$HANDOFF_PATH" 2>/dev/null || true

    printf '\n## Log\n\n'

    log_count=$(yq '.log | length' "$HANDOFF_PATH")
    max=5
    shown=0
    j=0
    while [ "$j" -lt "$log_count" ] && [ "$shown" -lt "$max" ]; do
        date=$(    yq ".log[$j].date    // \"-\"" "$HANDOFF_PATH")
        summary=$( yq ".log[$j].summary // \"-\"" "$HANDOFF_PATH")
        commits=$( yq ".log[$j].commits | map(.sha) | join(\", \")" "$HANDOFF_PATH" 2>/dev/null || echo "")
        if [ -n "$commits" ] && [ "$commits" != "null" ]; then
            printf -- '- %s: %s [%s]\n' "$date" "$summary" "$commits"
        else
            printf -- '- %s: %s\n' "$date" "$summary"
        fi
        j=$(( j + 1 ))
        shown=$(( shown + 1 ))
    done

} > "$HANDOFF_MD"

echo "wrote: $HANDOFF_MD" >&2

# ---------------------------------------------------------------------------
# Generate .ctx/HANDOVER.md  — ASCII dependency/flow diagram
# ---------------------------------------------------------------------------

HANDOVER_MD="$CTX_DIR/HANDOVER.md"

{
    printf '# Handover — %s\n\n' "$project"
    printf '_Generated: %s_\n\n' "$updated"

    printf '## Item Flow\n\n'
    printf '```\n'

    item_count=$(yq '.items | length' "$HANDOFF_PATH")
    i=0
    while [ "$i" -lt "$item_count" ]; do
        id=$(     yq ".items[$i].id       // \"-\""    "$HANDOFF_PATH")
        p=$(      yq ".items[$i].priority // \"-\""    "$HANDOFF_PATH")
        status=$( yq ".items[$i].status   // \"open\"" "$HANDOFF_PATH")
        title=$(  yq ".items[$i].name     // \"-\""    "$HANDOFF_PATH")
        deps=$(   yq ".items[$i].depends_on // []" "$HANDOFF_PATH" 2>/dev/null | yq 'join(", ")' 2>/dev/null || echo "")

        # Status symbol
        case "$status" in
            open)    sym='[ ]' ;;
            blocked) sym='[!]' ;;
            done)    sym='[x]' ;;
            *)       sym='[?]' ;;
        esac

        printf '  %s %s %s — %s\n' "$sym" "$p" "$id" "$title"
        if [ -n "$deps" ] && [ "$deps" != "null" ] && [ "$deps" != "" ]; then
            printf '       depends: %s\n' "$deps"
        fi
        i=$(( i + 1 ))
    done

    printf '```\n\n'

    printf '## Legend\n\n'
    printf '```\n'
    printf '  [ ]  open\n'
    printf '  [!]  blocked\n'
    printf '  [x]  done\n'
    printf '  P0   critical | P1 high | P2 normal\n'
    printf '```\n\n'

    printf '## Recent Sessions\n\n'
    printf '```\n'

    log_count=$(yq '.log | length' "$HANDOFF_PATH")
    max=5
    j=0
    while [ "$j" -lt "$log_count" ] && [ "$j" -lt "$max" ]; do
        session=$(  yq ".log[$j].session // \"-\""  "$HANDOFF_PATH")
        date=$(     yq ".log[$j].date    // \"-\""  "$HANDOFF_PATH")
        summary=$(  yq ".log[$j].summary // \"-\""  "$HANDOFF_PATH")
        printf '  s%s  %s  %s\n' "$session" "$date" "$summary"
        j=$(( j + 1 ))
    done

    printf '```\n'

} > "$HANDOVER_MD"

echo "wrote: $HANDOVER_MD" >&2
