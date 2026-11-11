# Changelog

## 1.1.0 — 2026-11-11

- **Dedicated instances**, as in the Windows version: a file or folder can open in its own Gryphmark, with its own
  settings, open folders, recent files, window and icon colour. On the Mac each one is an app of its own in
  Applications in your home folder (“Name (Gryphmark).app”, a copy that takes no disk space), so it can stay in
  the Dock. Right-click a file or a folder title in the Files panel → *Open in a dedicated instance*; from the
  command line, `--make-instance "Name"` with `--accent`, `--folder` (one or more), `--home`, `--read-only` and
  `--mode` makes one that always starts read-only and in a given view. Gryphmark rebuilds its instances when it
  is updated, and when their colour was changed from inside them. They never take over Markdown files in the
  Finder.
- **`[[name]]` links** in the GitHub view, as in a wiki: `[[name]]`, `[[name|text]]` and `[[name#heading]]` open
  the Markdown file of that name in the folders of the Files panel or next to the document, the nearest one when
  two share the name. A name that matches no file is shown in red, so broken links can be seen without clicking.
  Editing a paragraph in the visual view no longer escapes its `[[…]]` brackets when saving.
- **Links between the folders of the Files panel**: a document inside one of them can link to, and show pictures
  from, every folder of the panel, and `../` links resolve as on disk. A document opened from anywhere else still
  reaches only its own folder.

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
