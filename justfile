# atelier — personal dev workflow plugin

# Set up local git hooks and install the plugin. Run once after cloning.
init:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> atelier: plugin init"

    # 1. Wire local hooks
    git config core.hooksPath .githooks
    chmod +x .githooks/pre-commit .githooks/post-commit .githooks/pre-push
    echo "    hooks: .githooks wired"

    # 2. Verify claude is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "    ERROR: 'claude' not on PATH — install Claude Code first"
        echo "    https://claude.ai/code"
        exit 1
    fi

    # 3. Register local marketplace (self-contained in this repo)
    REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
    claude plugin marketplace add "$REPO_DIR" 2>/dev/null || \
        claude plugin marketplace update atelier 2>/dev/null || true
    echo "    marketplace: atelier registered"

    # 4. Install / reinstall plugin
    claude plugin uninstall atelier --force 2>/dev/null || true
    claude plugin install atelier@atelier
    echo "    plugin: atelier installed"

    echo ""
    echo "==> Done. Restart Claude Code to apply."
    echo "    Tip: also run 'just init' in ~/dev/sanctum for the companion plugin."

# Reinstall plugin without re-running full init
reinstall:
    #!/usr/bin/env bash
    claude plugin marketplace update atelier 2>/dev/null || true
    claude plugin uninstall atelier --force 2>/dev/null || true
    claude plugin install atelier@atelier
    echo "[atelier] reinstalled — restart Claude Code to apply"
