# Changelog

## 1.4.0 — 2026-11-13

- **Autosave**, on by default: a file with a name saves itself 1.5 seconds after you stop typing. A switch in the
  toolbar, and File → Autosave, turn it on and off. It never writes over a change made by another program (the
  live reload asks first), and never a new untitled document: that one is saved by itself once it has a name.
- **The scrollbar of the Visual view is at the window's edge.** In a window wider than the 980 px text column it
  stood at the edge of the column, with a wide empty margin to its right. The column is the same width as before.
- Saving takes the text and marks it saved in one step: a key pressed while a save was under way could be left out
  of the file and of the next save.

## 1.3.0 — 2026-11-12

- **The folders of the Files panel work as on Windows.** Each folder has its own colour: tones of the theme colour,
  multicolour, or none, and any folder can take one of twelve colours by hand (right-click its name → Colour).
- **Pin to top**: a pinned folder goes first and shows a pin. **Move up** and **Move down** change the order by hand.
- **The ⋯ button of the Files panel**: order of the folders (order opened, name A → Z or Z → A, recently modified
  first), their colours, and what opens at start.
- **Folders at start** (also in the File menu): reopen the folders of the last session, start clean, or start with
  only the pinned folders.
- The right-click menu of a folder adds *Copy path*; closing a folder also unpins it and forgets its colour.

## 1.2.0 — 2026-11-12

- **The open file stands out in the Files panel**: a filled band in the window's colour (it was only bold), and the
  folders down to it open, as on Windows.
- **Panels of any size**: drag the divider beside the sidebar (180 to 700 points; it was 240 to 420) and the new divider
  between Files and Contents. Each window, and each dedicated instance, keeps the sizes.
- **Convert to TXT**: right-click a file in the Files panel. A .txt is written next to it as the document reads in the
  GitHub view: headings underlined, lists with bullets or numbers, tables in columns, links with their address. The
  Markdown file is not changed, and an existing .txt is never overwritten (`name (2).txt`).
- The Files panel has *Collapse all* (a button and the right-click menu) and *Refresh* in its right-click menus.

## 1.1.2 — 2026-11-12

- A Markdown file with an HTML table whose `<tbody>` is empty (pandoc writes one for every one-row table of a Word
  document) opened as a blank page, with no message. The editor library (TOAST UI Editor 3.2.2) failed on that table;
  its code is now corrected in the bundle, and `scripts/web.sh` corrects it again on every rebuild.
- If the editor library ever fails on a document again, the GitHub view still shows all of it, the visual and Markdown
  views say what happened instead of staying blank, and saving writes the file back exactly as it is on disk.

## 1.1.1 — 2026-11-12

- Installing an update quit every dedicated instance along with Gryphmark, because they run an executable of the
  same name. The installer now quits only the Gryphmark in Applications; the dedicated instances stay open.

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
