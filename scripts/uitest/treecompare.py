#!/usr/bin/env python3
"""Tree comparison helpers for uitest (reads .mindmap JSON, docs/FORMAT.md format).

Subcommands:
  identical A B              exit 0 if trees identical (id/text/parent/order); else print diff summary
  parents A B                print IDENTICAL (exit 0) if sorted id/parent-id pairs are equal,
                             IGNORING only child order;
                             else print diff summary and exit 1
  parentof TEXT A            print parent text of first (BFS) node whose text == TEXT
  lastchild TEXT A           print text of last child of first node whose text == TEXT (none if no children)
  count A                    print node count
  findtext TEXT A            print count of nodes whose text == TEXT exactly
"""
import json
import sys
from collections import deque


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


def canonical_id(value):
    return value.lower()


def parent_snapshot(doc):
    return sorted((canonical_id(nid), canonical_id(parent) if parent else 'ROOT')
                  for nid, _, parent in walk(doc))


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
        # IDs are serialized product data. Ignore only sibling order; changing
        # an ID is a real structural regression because links/offsets key on it.
        doc_a, doc_b = load(sys.argv[2]), load(sys.argv[3])
        a, b = parent_snapshot(doc_a), parent_snapshot(doc_b)
        if a == b:
            print('IDENTICAL')
            sys.exit(0)
        pa, pb = dict(a), dict(b)
        rows_a, rows_b = list(walk(doc_a)), list(walk(doc_b))
        id2text_a = {canonical_id(nid): text for nid, text, _ in rows_a}
        id2text_b = {canonical_id(nid): text for nid, text, _ in rows_b}
        text2id_a = {text: canonical_id(nid) for nid, text, _ in rows_a}
        text2id_b = {text: canonical_id(nid) for nid, text, _ in rows_b}
        added = sorted(set(pb) - set(pa))
        removed = sorted(set(pa) - set(pb))
        moved = sorted(nid for nid in set(pa) & set(pb) if pa[nid] != pb[nid])
        reids = sorted(text for text in set(text2id_a) & set(text2id_b)
                       if text2id_a[text] != text2id_b[text])
        parts = [f'nodes {len(pa)}->{len(pb)}']
        if added:
            parts.append('added=' + ','.join(
                f'{id2text_b.get(nid, "?")}[{nid}]->{pb[nid]}' for nid in added[:5]))
        if removed:
            parts.append('removed=' + ','.join(
                f'{id2text_a.get(nid, "?")}[{nid}]->{pa[nid]}' for nid in removed[:5]))
        if moved:
            parts.append('moved=' + ','.join(
                f'{id2text_b.get(nid, "?")}[{nid}]:{pa[nid]}->{pb[nid]}' for nid in moved[:5]))
        if reids:
            parts.append('reid=' + ','.join(
                f'{text}:{text2id_a[text]}->{text2id_b[text]}' for text in reids[:5]))
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
