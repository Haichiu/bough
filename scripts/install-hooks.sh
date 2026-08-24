#!/bin/bash
# Installs a pre-commit hook that runs the logic checks before every commit.
set -e
cd "$(dirname "$0")/.."
cat > .git/hooks/pre-commit <<'HOOK'
#!/bin/bash
cd "$(git rev-parse --show-toplevel)"
echo "==> pre-commit: MindFlowChecks…"
if ! swift run MindFlowChecks > /tmp/mf-precommit.log 2>&1; then
    echo "✗ Checks failed — commit aborted. Last output:"
    tail -20 /tmp/mf-precommit.log
    exit 1
fi
echo "✓ checks passed"
HOOK
chmod +x .git/hooks/pre-commit
echo "pre-commit hook installed"