# Changelog

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
