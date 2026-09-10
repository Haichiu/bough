# Bough

**A native macOS mind-mapping app that stays out of your way.**
一款不打擾你的 macOS 原生心智圖工具。

Bough is written from scratch in Swift and SwiftUI. No Electron, no account,
no network, no subscription, no AI assistant trying to finish your thoughts.
You press <kbd>Tab</kbd>, a branch grows. That is the whole idea.

---

## Why another mind map?

Mind mapping used to be fast. You typed, you pressed Tab, the map grew as
quickly as you could think. Then the good tools grew login screens, sync
conflicts, upgrade prompts, and an AI button where the New Topic button used
to be.

Bough is an attempt to keep the fast part and throw away the rest.

| | |
|---|---|
| **Keyboard first** | <kbd>Tab</kbd> for a child, <kbd>Return</kbd> for a sibling, arrows to move. Your hands never need the mouse. |
| **Your files are yours** | Every map is one `.mindmap` file, which is plain JSON with a [documented format](docs/FORMAT.md). Open it in any text editor. Nothing is locked in. |
| **Nothing to sign up for** | No account, no cloud, no telemetry. It has never made a network request and it does not intend to start. |
| **Native, not a web page** | Swift + SwiftUI. It launches instantly and it does not eat a gigabyte of memory to draw rectangles. |
| **Finished, not featured** | Undo goes back a hundred steps. Autosave fires 1.5 seconds after you stop typing, and again on quit. Close a tab by accident and <kbd>⌘⇧T</kbd> brings it back. |

## What it does

- **Four layouts** — logic (right), balanced, fishbone, bracket. Switch any time with <kbd>⌥⌘1</kbd>–<kbd>⌥⌘4</kbd>.
- **Boundaries** — <kbd>⇧⌘B</kbd> draws a frame around a branch and everything visible under it.
- **Summaries** — bracket several adjacent topics together and annotate them.
- **Relationship links** — draw a labelled arc between any two topics, across branches.
- **Outline mode** — the same document as a keyboard-navigable tree.
- **Focus and presentation** — <kbd>⌘⌥F</kbd> hides the entire interface; <kbd>⌘⌥P</kbd> reveals the map level by level for an audience.
- **Import** — Markdown outlines, OPML, FreeMind `.mm`, or a bullet list straight off the clipboard.
- **Export** — Markdown, OPML, FreeMind, PNG, PDF, and real vector SVG. Any single branch can be exported on its own.
- **Images** — drag a file onto a topic or paste a screenshot. Embedded in the document, so sharing never breaks it.
- **Themes** — several restrained colour schemes; each one changes the shape of the map, not only its palette.

## Install

Download the latest `.dmg` from [Releases](../../releases), drag Bough to
Applications, and open it. The first launch opens a tutorial map — follow it
and you have learned the app.

Building it yourself needs only the Xcode Command Line Tools:

```bash
git clone https://github.com/Haichiu/bough.git
cd bough
bash scripts/package.sh        # produces ~/Desktop/Bough.app
```

## Documentation

- **[使用手冊 / Full manual](docs/MANUAL.md)** — every feature and every shortcut, in Traditional Chinese.
- **[File format](docs/FORMAT.md)** — the `.mindmap` JSON schema, in full.
- **[Testing](docs/TESTING.md)** — the acceptance checklist.

## For developers

```bash
swift run Bough             # run from source
swift run MindFlowChecks    # the assertion suite
bash scripts/package.sh     # package the .app
```

The code is one library target, `MindFlowKit`, holding the model, layout
engine, view model, file IO and all SwiftUI views; a thin `Bough` executable
that supplies `@main`; and `Checks`, an assertion suite that runs as a plain
executable so it works with the Command Line Tools alone, no Xcode required.

`MindFlowKit` still carries the project's former name. Renaming a module is
churn that no user can see, so it was left alone.

## Status

Bough is used daily by its author and is still moving quickly. The document
format is stable and every release reads files written by earlier ones.

## Licence

MIT. See [LICENSE](LICENSE).
