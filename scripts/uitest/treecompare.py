#!/usr/bin/env python3
"""Tree comparison helpers for uitest (reads .mindmap JSON, docs/FORMAT.md format).

Subcommands:
  identical A B              exit 0 if trees identical (id/text/parent/order); else print diff summary
  parents A B                print IDENTICAL (exit 0) if text/parent-text multisets are equal,
                             IGNORING internal ids and child order;
                             else print diff summary and exit 1
  parentof TEXT A            print parent text of first (BFS) node whose text == TEXT
  lastchild TEXT A           print text of last child of first node whose text == TEXT (none if no children)
  count A                    print node count
  findtext TEXT A            print count of nodes whose text == TEXT exactly
"""
import json
import sys
from collections import Counter, deque


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def walk(doc):
    """Yields (id, text, parent_id) in document order (BFS)."""
    q = deque([(doc['root'], None)])
    while q:
        node, parent = q.popleft()
        yield node['id'], node.get('text', ''), parent
        for c in node.get('children', []):
            q.append((c, node['id']))


def children_of(doc, parent_id):
    q = deque([doc['root']])
    while q:
        node = q.popleft()
        if node['id'] == parent_id:
            return node.get('children', [])
        q.extend(node.get('children', []))
    return None


def find_by_text(doc, text):
    q = deque([doc['root']])
    while q:
        node = q.popleft()
        if node.get('text', '') == text:
            return node
        q.extend(node.get('children', []))
    return None


def snapshot(doc):
    return {nid: (text, parent) for nid, text, parent in walk(doc)}


def parent_snapshot(doc):
    rows = list(walk(doc))
    id2text = {nid: text for nid, text, _ in rows}
    return Counter((text, id2text.get(parent, 'ROOT') if parent else 'ROOT')
                   for _, text, parent in rows)


def main():
    cmd = sys.argv[1]
    if cmd == 'identical':
        a, b = load(sys.argv[2]), load(sys.argv[3])
        sa, sb = snapshot(a), snapshot(b)
        if sa == sb:
            sys.exit(0)
        added = set(sb) - set(sa)
        removed = set(sa) - set(sb)
        moved = [k for k in set(sa) & set(sb)
                 if sa[k][1] != sb[k][1]]
        retyped = [k for k in set(sa) & set(sb)
                   if sa[k][1] == sb[k][1] and sa[k][0] != sb[k][0]]
        id2t_a = {nid: t for nid, (t, _) in sa.items()}
        id2t_b = {nid: t for nid, (t, _) in sb.items()}
        parts = [f'nodes {len(sa)}->{len(sb)}']
        if added:
            parts.append('added=' + ','.join(id2t_b.get(k, k) for k in sorted(added)[:5]))
        if removed:
            parts.append('removed=' + ','.join(id2t_a.get(k, k) for k in sorted(removed)[:5]))
        if moved:
            parts.append('moved=' + ','.join(
                f'{id2t_b.get(k, k)}:{id2t_a[sa[k][1]] if sa[k][1] in id2t_a else "?"}->{id2t_b[sb[k][1]] if sb[k][1] in id2t_b else "?"}'
                for k in sorted(moved)[:5]))
        if retyped:
            parts.append('retyped=' + ','.join(id2t_b.get(k, k) for k in sorted(retyped)[:5]))
        print(' '.join(parts))
        sys.exit(1)
    if cmd == 'parents':
        # Compare observable tree structure: fixture text labels and their
        # parent labels. Internal ids and sibling order are persistence details.
        a, b = parent_snapshot(load(sys.argv[2])), parent_snapshot(load(sys.argv[3]))
        if a == b:
            print('IDENTICAL')
            sys.exit(0)
        added = list((b - a).elements())
        removed = list((a - b).elements())
        parts = [f'nodes {sum(a.values())}->{sum(b.values())}']
        if added:
            parts.append('added=' + ','.join(f'{n}->{p}' for n, p in sorted(added)[:5]))
        if removed:
            parts.append('removed=' + ','.join(f'{n}->{p}' for n, p in sorted(removed)[:5]))
        print(' '.join(parts))
        sys.exit(1)
    if cmd == 'parentof':
        text, path = sys.argv[2], sys.argv[3]
        doc = load(path)
        node = find_by_text(doc, text)
        if node is None:
            print('MISSING')
            sys.exit(1)
        for nid, t, parent in walk(doc):
            if nid == node['id']:
                id2t = {n: t2 for n, t2, _ in walk(doc)}
                print(id2t.get(parent, 'ROOT') if parent else 'ROOT')
                return
    if cmd == 'lastchild':
        text, path = sys.argv[2], sys.argv[3]
        kids = children_of(load(path), find_by_text(load(path), text)['id']) if find_by_text(load(path), text) else []
        print(kids[-1].get('text', '') if kids else 'NONE')
        return
    if cmd == 'count':
        print(sum(1 for _ in walk(load(sys.argv[2]))))
        return
    if cmd == 'findtext':
        text = sys.argv[2]
        hits = [t for _, t, _ in walk(load(sys.argv[3])) if t == text]
        print(len(hits))
        return
    print(f'unknown cmd {cmd}', file=sys.stderr)
    sys.exit(2)


if __name__ == '__main__':
    main()
