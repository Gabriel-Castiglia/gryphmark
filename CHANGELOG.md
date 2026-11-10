# Changelog

## 1.0.1 — 2026-11-10

- The window could be made narrower than its content, which then lost both edges: the toolbar, the sidebar and the
  document were cut off. The window now keeps a minimum size, a saved size that is too small is enlarged, and in a
  narrow window the formatting buttons that do not fit move to a ⋯ menu. A wider window widens the document, not
  the sidebar.
- The app starts with the sample document until you open a file of your own. Before, the sample showed only on
  the very first start.
- Dark theme: list items and table headers in the visual view were almost black on the dark page; they now have
  the colour of the rest of the text (also fixed in Gryphmark 1.8.1 for Windows).

## 1.0.0 — 2026-11-10

First version for macOS, made from Gryphmark 1.8.0 for Windows.

- The same editor page: Visual, Markdown and GitHub views, GitHub alerts, Mermaid, math, footnotes and emoji,
  the HTML of documents cleaned with DOMPurify, saving that keeps the original Markdown, line endings and BOM.
- Live reload in place, with the scroll kept in every view: writes, saves by renaming a new file over the old one,
  deletes and re-creations are followed by kernel file events; the page keeps running behind other windows.
  With unsaved changes the window asks first.
- A native window (AppKit and SwiftUI) per document: toolbar, sidebar with folders and contents, find and
  replace, zoom, export to HTML, print and PDF, crash recovery, update check, Edit and Read only.
- English and Spanish, switched at run time; menus with the macOS shortcuts.
- Theme as macOS, light or dark, and the twelve colours of the Windows version, which also tint the Dock icon.
- Links follow the Windows rules: only web pages, e-mail, Markdown files, pictures and PDFs open; other files are
  shown in the Finder.
- Installer package in English and Spanish, for macOS 15 or later on Apple silicon; `--self-test` in a real
  window.
