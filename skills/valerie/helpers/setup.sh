#!/bin/sh
# valerie setup — detect backend, prompt for choices, write config
# Usage: sh setup.sh
# Writes: .claude-plugin/valerie.local.yaml

set -e

CONFIG_DIR="$(dirname "$0")/../../.claude-plugin"
CONFIG_FILE="$CONFIG_DIR/valerie.local.yaml"

mkdir -p "$CONFIG_DIR"

echo ""
echo "valerie setup"
echo "============="
echo ""

# --- Backend detection ---
DOOB_FOUND=0
if command -v doob >/dev/null 2>&1; then
    DOOB_FOUND=1
    DOOB_VERSION=$(doob --version 2>/dev/null || echo "unknown")
    echo "doob detected: $DOOB_VERSION"
else
    echo "doob not found on PATH."
fi

# --- Backend choice ---
echo ""
echo "Choose a todo backend:"
echo "  1) doob  — Rust + SurrealKV, agent-first, recommended"
echo "  2) sqlite — lightweight fallback, sh/nu wrapper script"
echo ""
printf "Backend [1/2]: "
read -r BACKEND_CHOICE

case "$BACKEND_CHOICE" in
    2)
        BACKEND="sqlite"
        ;;
    *)
        BACKEND="doob"
        ;;
esac

# --- If doob chosen but not found, offer install ---
if [ "$BACKEND" = "doob" ] && [ "$DOOB_FOUND" = "0" ]; then
    echo ""
    echo "doob is not installed. Install options:"
    echo "  a) cargo install doob          (from crates.io — not yet published)"
    echo "  b) cargo install --path <dir>  (from local clone)"
    echo "  c) Skip — I will install manually"
    echo ""
    printf "Choice [a/b/c]: "
    read -r INSTALL_CHOICE
    case "$INSTALL_CHOICE" in
        b)
            printf "Path to doob repo: "
            read -r DOOB_PATH
            echo "Running: cargo install --path $DOOB_PATH"
            cargo install --path "$DOOB_PATH"
            ;;
        c)
            echo "Skipping install. Re-run setup after installing doob."
            ;;
        *)
            echo "crates.io install not yet available. Use option b or c."
            ;;
    esac
fi

# --- Shell choice ---
echo ""
echo "Choose a shell for generated scripts:"
echo "  1) sh   — POSIX, works everywhere"
echo "  2) nu   — Nushell, richer output"
echo ""
printf "Shell [1/2]: "
read -r SHELL_CHOICE

case "$SHELL_CHOICE" in
    2)
        SHELL_PREF="nu"
        ;;
    *)
        SHELL_PREF="sh"
        ;;
esac

# --- Write config ---
cat > "$CONFIG_FILE" <<EOF
# valerie local configuration — auto-generated, safe to edit
backend: $BACKEND
shell: $SHELL_PREF
configured: $(date +%Y-%m-%d)
EOF

echo ""
echo "Config written to: $CONFIG_FILE"
echo ""
echo "  backend: $BACKEND"
echo "  shell:   $SHELL_PREF"
echo ""
echo "Setup complete. Valerie will use these settings going forward."
