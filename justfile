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

    # 3. Register bazaar marketplace (add if new, update if already registered)
    if ! claude plugin marketplace add 89jobrien/bazaar 2>/dev/null; then
        claude plugin marketplace update bazaar || \
            { echo "    ERROR: failed to register bazaar marketplace"; exit 1; }
    fi
    echo "    marketplace: bazaar registered"

    # 4. Install / reinstall plugin
    claude plugin uninstall atelier --force 2>/dev/null || true
    claude plugin install atelier@bazaar
    echo "    plugin: atelier installed"

    # 5. Mirror into Codex if available on this machine
    if [ -d "${CODEX_HOME:-$HOME/.codex}" ]; then
        ./bin/sync-codex
        echo "    codex: atelier mirrored"
    fi

    echo ""
    echo "==> Done. Restart Claude Code to apply."
    echo "    Tip: also run 'just init' in ~/dev/sanctum for the companion plugin."

# Reinstall plugin without re-running full init
reinstall:
    #!/usr/bin/env bash
    set -euo pipefail
    claude plugin marketplace update bazaar 2>/dev/null || true
    claude plugin uninstall atelier --force 2>/dev/null || true
    claude plugin install atelier@bazaar
    if [ -d "${CODEX_HOME:-$HOME/.codex}" ]; then
        ./bin/sync-codex
    fi
    echo "[atelier] reinstalled — restart Claude Code to apply"

sync-codex:
    #!/usr/bin/env bash
    set -euo pipefail
    ./bin/sync-codex
