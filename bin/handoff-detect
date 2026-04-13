#!/bin/sh
# handoff-detect.sh — Locate the HANDOFF.*.yaml file for the current repo.
#
# Usage:
#   handoff-detect            # print full path; exit 0 if found, 2 if not
#   handoff-detect --name     # filename only
#   handoff-detect --root     # repo root path
#   handoff-detect --project  # project name (basename of repo root)
#
# Exit codes:
#   0  file found (or migration succeeded)
#   1  not in a git repo
#   2  file not found (expected path printed to stdout)

set -eu

MODE=path

while [ $# -gt 0 ]; do
    case "$1" in
        --name)    MODE=name;    shift ;;
        --root)    MODE=root;    shift ;;
        --project) MODE=project; shift ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Require git
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "error: not in a git repository" >&2
    exit 1
}

PROJECT=$(basename "$REPO_ROOT")
CWD_BASE=$(basename "$PWD")

# Naming: if cwd IS the repo root, use "workspace"; otherwise use cwd basename
if [ "$CWD_BASE" = "$PROJECT" ]; then
    FILENAME="HANDOFF.${PROJECT}.workspace.yaml"
else
    FILENAME="HANDOFF.${PROJECT}.${CWD_BASE}.yaml"
fi

TARGET="${REPO_ROOT}/.ctx/${FILENAME}"

# Return early for metadata flags (no file check needed)
if [ "$MODE" = "root" ]; then
    echo "$REPO_ROOT"
    exit 0
fi
if [ "$MODE" = "project" ]; then
    echo "$PROJECT"
    exit 0
fi
if [ "$MODE" = "name" ]; then
    echo "$FILENAME"
    exit 0
fi

# Check canonical location
if [ -f "$TARGET" ]; then
    echo "$TARGET"
    exit 0
fi

# Migration fallback: look for any HANDOFF.*.yaml at repo root
OLD=$(ls "${REPO_ROOT}"/HANDOFF.*.yaml 2>/dev/null | head -1)
if [ -n "$OLD" ]; then
    SCRIPT_DIR=$(dirname "$0")
    NEW=$(sh "${SCRIPT_DIR}/migrate-handoff.sh" "$REPO_ROOT" "$OLD") || exit 1
    echo "$NEW"
    exit 0
fi

# Not found
echo "$TARGET"
exit 2
