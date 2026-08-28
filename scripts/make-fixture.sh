#!/usr/bin/env bash
# T-002 — MindFlow fixture map generator.
#
# Usage:  bash scripts/make-fixture.sh   # generates all three sizes into scripts/fixtures/
#
# Output format: docs/FORMAT.md (MindDocument JSON, tolerant decode —
# only id/text/children are emitted; every other field uses its default).
# Nodes form a balanced BFS tree; text is "N-0042" so automated tooling
# (uitest/, grep) can address nodes deterministically. Node ids derive from
# the node index, so generation is reproducible.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/scripts/fixtures"
mkdir -p "$OUT_DIR"

python3 - "$OUT_DIR" <<'PY'
import json, os, sys

out_dir = sys.argv[1]

SIZES = [
    ("small-20", 20, 4, "logicRight"),
    ("medium-200", 200, 5, "balanced"),
    ("large-1500", 1500, 6, "balanced"),
]


def gen_tree(n: int, branch: int):
    counter = 0

    def new_node():
        nonlocal counter
        i = counter
        counter += 1
        # Deterministic UUID derived from the node index.
        return {
            "id": f"{i:08x}-0000-4000-8000-{i:012x}",
            "text": f"N-{i:04d}",
            "children": [],
        }

    root = new_node()
    queue = [root]
    while counter < n:
        parent = queue.pop(0)
        for _ in range(min(branch, n - counter)):
            child = new_node()
            parent["children"].append(child)
            queue.append(child)
    assert counter == n, (counter, n)
    return root


for name, n, branch, direction in SIZES:
    doc = {
        "title": f"fixture {name}",
        "themeName": "ocean",
        "directionName": direction,
        "root": gen_tree(n, branch),
        "links": [],
        "offsets": {},
    }
    path = os.path.join(out_dir, f"{name}.mindmap")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"wrote {path} ({n} nodes, branch={branch}, direction={direction})")
PY

echo "Verifying JSON parses:"
for f in "$OUT_DIR"/*.mindmap; do
  python3 -c "import json; d=json.load(open('$f')); print('$f', 'OK,', len(json.dumps(d)), 'bytes')"
done
