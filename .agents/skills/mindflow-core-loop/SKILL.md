---
name: mindflow-core-loop
description: Keep MindFlow product work focused on evidence-backed improvements to capturing, editing, restructuring, navigating, and safely preserving ideas. Use for every MindFlow feature, UX, bug-fix, or product-direction task.
---

# MindFlow Core Loop

## Product promise

Let people capture, expand, reorganize, navigate, and preserve ideas without the interface interrupting their thinking.

Prioritize:

1. Tab/Return creation, focus, editing, commit, and cancel.
2. Drag reparenting, sibling ordering, feedback, and undo.
3. Selection, pan, zoom, fit, keyboard navigation, and large-map orientation.
4. Autosave, reopen, recovery, document isolation, and bounded storage.

## Evidence gate

Before changing code, state:

- the observable friction;
- the shortest reproduction;
- the expected behavior;
- why it affects the product promise;
- the smallest complete change;
- the direct behavioral check.

Valid evidence is a user report, a reproduced bug, a direct probe, or a clear contradiction between current behavior and an existing interaction promise. Speculation is not evidence.

If evidence is missing, report at most three hypotheses for human testing and stop. Do not implement them.

## One useful loop

Work on one friction at a time. Trace its execution path, make the smallest end-to-end correction, directly verify the original interaction, then run only the smallest relevant regression check.

A build or broad test suite does not prove a UX improvement. Completion requires evidence that the original friction is gone.

Unless the owner explicitly requests it, do not add adjacent features, bump versions, create tags, package a DMG, update the changelog, or run repeated full regressions.

When no evidence-backed core friction remains, say: `目前沒有足夠證據支持下一次修改，需要實際使用回饋。` Then stop.
