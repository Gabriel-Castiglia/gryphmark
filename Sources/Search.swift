// Vigia: the search box above the Files tree: by file name or in the text of the files.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 17, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// It looks in every folder of the Files panel, at the files the tree shows (Markdown, no hidden
// files), with no difference between capitals and small letters or accented and plain letters
// ("busqueda" finds "búsqueda"). While the box has text the tree gives its place to the results;
// emptied (or Esc) the tree comes back as it was. A click on a line of text opens the file and the
// document's own find bar on that place. The Windows version (MainWindow.Search.cs) follows the
// same rules and limits.

import AppKit
import SwiftUI

/// One piece of a line: the text before the match, the match as it is written in the file, and the
/// text after it. `occurrence` counts the same words (capitals aside) before it in the file, so the
/// document's find bar can go to this one.
struct SearchSnippet: Hashable {
    let line: Int
    let before, hit, after: String
    let occurrence: Int
    var text = ""                 // the whole line, so the page can tell the match in a view that hides Markdown
}

struct SearchHit: Identifiable, Hashable {
    let url: URL
    let folder: String            // where it is, from the panel folder down (shown in grey)
    var name: SearchSnippet?      // by name: the name split around the match
    var lines: [SearchSnippet] = []
    var count = 0                 // matches in the file (more than the lines shown)
    var id: String { url.path }
}

enum TreeSearch {
    static let maxBytes = 2_000_000       // bigger files are left out of a search in the text
    static let maxMatches = 1000          // a search in the text stops here and says so
    static let maxNames = 500
    static let linesPerFile = 5
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The files the tree shows, panel folder by panel folder; a folder inside another one is not read twice.
    static func files(_ roots: [String], cancelled: () -> Bool = { false }) -> [(url: URL, root: URL)] {
        var seen = Set<String>(), out: [(URL, URL)] = []
        for r in roots {
            let root = URL(fileURLWithPath: r).standardizedFileURL
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                if cancelled() { return out }
                let x = u.pathExtension.lowercased()
                guard x != "txt", LinkPolicy.markdown.contains(x),
                      (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                if seen.insert(TreeState.canonical(u.path)).inserted { out.append((u.standardizedFileURL, root)) }
            }
        }
        return out
    }

    static func folder(of url: URL, in root: URL) -> String {
        let dir = url.deletingLastPathComponent().path, base = root.deletingLastPathComponent().path
        return dir.hasPrefix(base + "/") ? String(dir.dropFirst(base.count + 1)) : dir
    }

    /// A piece of `text` around `r`: up to 40 characters before and 90 after, with … where it was cut.
    static func snippet(_ text: Substring, _ r: Range<String.Index>, line: Int, occurrence: Int) -> SearchSnippet {
        var before = String(text[text.startIndex ..< r.lowerBound])
        before = String(before.drop { $0 == " " || $0 == "\t" })
        if before.count > 40 { before = "…" + before.suffix(40) }
        var after = String(text[r.upperBound...])
        if after.count > 90 { after = after.prefix(90) + "…" }
        return SearchSnippet(line: line, before: before, hit: String(text[r]), after: after, occurrence: occurrence, text: String(text))
    }

    static func byName(_ q: String, roots: [String], cancelled: () -> Bool = { false }) -> [SearchHit] {
        var out: [SearchHit] = []
        for (u, root) in files(roots, cancelled: cancelled) {
            let name = u.lastPathComponent
            guard let r = name.range(of: q, options: options) else { continue }
            out.append(SearchHit(url: u, folder: folder(of: u, in: root), name: snippet(name[...], r, line: 0, occurrence: 0), count: 1))
            if out.count >= maxNames { break }
        }
        return out
    }

    /// Every match in the text of the files. `cut` is true when it stopped at maxMatches.
    static func byContent(_ q: String, roots: [String], cancelled: () -> Bool = { false }) -> (hits: [SearchHit], total: Int, cut: Bool) {
        var out: [SearchHit] = [], total = 0
        for (u, root) in files(roots, cancelled: cancelled) {
            if cancelled() { break }
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxBytes, let text = try? DocWindow.read(u).text else { continue }
            guard text.range(of: q, options: options) != nil else { continue }
            var hit = SearchHit(url: u, folder: folder(of: u, in: root))
            var n = 0
            text.enumerateSubstrings(in: text.startIndex..., options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
                n += 1
                let line = text[lineRange]
                var from = line.startIndex
                while from < line.endIndex, let r = line.range(of: q, options: options, range: from ..< line.endIndex) {
                    hit.count += 1; total += 1
                    if hit.lines.count < linesPerFile {
                        // how many times the very same words (capitals aside) come before this one
                        let word = String(line[r])
                        var k = 0, at = text.startIndex
                        while let o = text.range(of: word, options: .caseInsensitive, range: at ..< r.lowerBound) { k += 1; at = o.upperBound }
                        hit.lines.append(snippet(line, r, line: n, occurrence: k))
                    }
                    if total >= maxMatches { stop = true; break }
                    from = r.upperBound > r.lowerBound ? r.upperBound : line.index(after: r.lowerBound)
                }
            }
            out.append(hit)
            if total >= maxMatches { return (out, total, true) }
        }
        return (out, total, false)
    }
}

/// The search of one window: what is typed, the results, and which row the arrow keys are on.
final class SearchState: ObservableObject {
    struct Row: Hashable { let hit: Int; let line: Int? }    // line nil: the file itself (by name)

    @Published var query = "" { didSet { if query != oldValue { schedule() } } }
    @Published private(set) var results: [SearchHit] = []
    @Published private(set) var rows: [Row] = []
    @Published private(set) var info = ""
    @Published private(set) var busy = false
    @Published var selected: Int?
    weak var field: NSSearchField?
    private var work: Task<Void, Never>?
    private var engine: Task<([SearchHit], Int, Bool), Never>?

    var active: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A new search a moment after the typing stops (at once with `delay` 0); the one running is dropped.
    func schedule(delay: Double = 0.25) {
        work?.cancel(); engine?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; rows = []; info = ""; busy = false; selected = nil; return }
        work = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            await self.run(q)
        }
    }

    /// Runs the search now and waits for it (the self-test uses it).
    @MainActor
    func run(_ q: String? = nil) async {
        let q = q ?? query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let roots = Prefs.shared.orderedFolders, byName = Prefs.shared.searchMode == "name"
        busy = true
        let task = Task.detached(priority: .userInitiated) { () -> ([SearchHit], Int, Bool) in
            if byName { let h = TreeSearch.byName(q, roots: roots) { Task.isCancelled }; return (h, h.count, h.count >= TreeSearch.maxNames) }
            let r = TreeSearch.byContent(q, roots: roots) { Task.isCancelled }
            return (r.hits, r.total, r.cut)
        }
        engine = task
        let (hits, total, cut) = await task.value
        guard !task.isCancelled else { return }
        busy = false
        results = hits
        rows = hits.enumerated().flatMap { i, h in byName ? [Row(hit: i, line: nil)] : h.lines.indices.map { Row(hit: i, line: $0) } }
        selected = nil
        let files = { (n: Int) in L(n == 1 ? "SearchUnitFile" : "SearchUnitFiles") }
        if hits.isEmpty { info = L("SearchNone") }
        else if byName { info = cut ? L("SearchTooManyNames", total) : L("SearchFiles", total, files(total)) }
        else {
            info = cut ? L("SearchTooMany", total)
                : L("SearchCount", total, L(total == 1 ? "SearchUnitMatch" : "SearchUnitMatches"), hits.count, files(hits.count))
        }
    }

    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        selected = selected.map { min(max($0 + by, 0), rows.count - 1) } ?? (by > 0 ? 0 : rows.count - 1)
    }

    func open(_ row: Row, in doc: DocWindow) {
        guard results.indices.contains(row.hit) else { return }
        let hit = results[row.hit]
        let line = row.line.flatMap { hit.lines.indices.contains($0) ? hit.lines[$0] : nil }
        Task { @MainActor in await doc.openFound(hit.url, find: line.map { ($0.hit, $0.occurrence, $0.text) }) }
    }

    func openSelected(in doc: DocWindow) {
        if let s = selected, rows.indices.contains(s) { open(rows[s], in: doc) } else if let first = rows.first { open(first, in: doc) }
    }

    /// Puts the caret in the box (Edit → Search in folders); the box may only appear a moment later.
    func focus(_ tries: Int = 10) {
        if let f = field, let w = f.window { w.makeFirstResponder(f); f.currentEditor()?.selectAll(nil); return }
        if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.focus(tries - 1) } }
    }
}

/// While a layout changes two sidebars can live for a moment: the box that is in a window is the one the search uses.
final class PanelSearchField: NSSearchField {
    weak var search: SearchState?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { search?.field = self } else if search?.field === self { search?.field = nil }
    }
}

/// The box itself: a native search field. ↑ ↓ go through the results, Return opens one, Esc empties it.
struct SearchBox: NSViewRepresentable {
    @ObservedObject var search: SearchState
    let doc: DocWindow

    func makeNSView(context: Context) -> PanelSearchField {
        let f = PanelSearchField()
        f.search = search
        f.placeholderString = L("SearchPlaceholder")
        f.sendsSearchStringImmediately = true
        f.focusRingType = .exterior
        f.controlSize = .small
        f.font = .systemFont(ofSize: 12)
        f.delegate = context.coordinator
        f.setAccessibilityIdentifier("treeSearch")
        f.stringValue = search.query
        return f
    }

    func updateNSView(_ f: PanelSearchField, context: Context) {
        if f.stringValue != search.query { f.stringValue = search.query }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let box: SearchBox
        init(_ b: SearchBox) { box = b }
        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSSearchField { box.search.query = f.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveDown(_:)): box.search.move(1); return true
            case #selector(NSResponder.moveUp(_:)): box.search.move(-1); return true
            case #selector(NSResponder.insertNewline(_:)): box.search.openSelected(in: box.doc); return true
            case #selector(NSResponder.cancelOperation(_:)): box.search.query = ""; return true
            default: return false
            }
        }
    }
}

/// Above the tree: the box and the choice between names and text.
struct TreeSearchBar: View {
    let doc: DocWindow
    @ObservedObject var search: SearchState
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(spacing: 5) {
            SearchBox(search: search, doc: doc).frame(height: 22)
            Picker("", selection: Binding(get: { prefs.searchMode }, set: { prefs.searchMode = $0; search.schedule(delay: 0) })) {
                Text(L("SearchName")).tag("name").help(L("SearchNameTip"))
                Text(L("SearchContent")).tag("content").help(L("SearchContentTip"))
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            .accessibilityIdentifier("treeSearchMode")
        }
        .padding(.horizontal, 10).padding(.bottom, 6)
    }
}

/// Text with the matched part marked in the highlight colour.
func marked(_ s: SearchSnippet, _ color: Color, size: CGFloat = 12) -> AttributedString {
    var hit = AttributedString(s.hit)
    hit.swiftUI.backgroundColor = color.opacity(0.38)
    hit.swiftUI.font = .system(size: size, weight: .semibold)
    var before = AttributedString(s.before), after = AttributedString(s.after)
    before.swiftUI.font = .system(size: size); after.swiftUI.font = .system(size: size)
    return before + hit + after
}

/// What takes the place of the tree while the box has text.
struct TreeSearchResults: View {
    let doc: DocWindow
    @ObservedObject var search: SearchState
    @ObservedObject var prefs: Prefs
    let current: URL?

    var body: some View {
        let byName = prefs.searchMode == "name"
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if search.busy { ProgressView().controlSize(.mini) }
                Text(search.busy ? L("Searching") : search.info).font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("treeSearchInfo")
            }
            .padding(.horizontal, 12).padding(.bottom, 4)
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { i, hit in
                        if byName, let name = hit.name {
                            row(SearchState.Row(hit: i, line: nil)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Label { Text(marked(name, prefs.highlight)).lineLimit(1) } icon: { Image(systemName: "doc.text") }
                                    Text(hit.folder).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                                        .padding(.leading, 22)
                                }
                            }
                        } else {
                            fileHeader(hit, i)
                            ForEach(hit.lines.indices, id: \.self) { k in
                                row(SearchState.Row(hit: i, line: k)) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(hit.lines[k].line)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                            .frame(minWidth: 22, alignment: .trailing)
                                        Text(marked(hit.lines[k], prefs.highlight)).lineLimit(2)
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                            if hit.count > hit.lines.count {
                                Text(L("SearchMore", hit.count - hit.lines.count)).font(.system(size: 10)).foregroundStyle(.secondary)
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: search.selected) { _, s in
                    if let s, search.rows.indices.contains(s) { proxy.scrollTo(search.rows[s], anchor: .center) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fileHeader(_ hit: SearchHit, _ i: Int) -> some View {
        let isCurrent = current.map { TreeState.canonical($0.path) == TreeState.canonical(hit.url.path) } == true
        return HStack(spacing: 5) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(hit.url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(hit.folder).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 4)
            Text("\(hit.count)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 5).background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(.vertical, 2).padding(.horizontal, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? prefs.highlight.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { Task { @MainActor in await doc.openFound(hit.url, find: nil) } }
        .help(hit.url.path)
    }

    private func row<C: View>(_ r: SearchState.Row, @ViewBuilder _ content: () -> C) -> some View {
        let on = search.selected.map { search.rows.indices.contains($0) && search.rows[$0] == r } == true
        return content()
            .padding(.vertical, 2).padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? prefs.highlight.opacity(0.3) : .clear))
            .contentShape(Rectangle())
            .onTapGesture { search.selected = search.rows.firstIndex(of: r); search.open(r, in: doc) }
            .id(r)
    }
}

extension DocWindow {
    /// Opens a file found by the search (or brings forward the window that has it) and, for a line of text,
    /// opens the find bar on that place.
    @MainActor
    func openFound(_ url: URL, find: (text: String, occurrence: Int, line: String)?) async {
        let url = url.standardizedFileURL
        var target = self
        if model.path != url {
            if let other = DocWindow.all.first(where: { $0.model.path == url }) {
                target = other; other.window?.makeKeyAndOrderFront(nil)
            } else {
                guard await confirmDiscard() else { return }
                await load(url)
                guard model.path == url else { return }
            }
        }
        guard let find else { return }
        let m = target.model
        m.findQuery = find.text; m.findCase = false; m.replaceVisible = false; m.findVisible = true
        // how many times these words (capitals aside) are in the file: when a view shows another number, the page
        // takes the match whose paragraph is most like this line (app.js, findAt)
        var total = 0
        if let text = try? DocWindow.read(url).text {
            var at = text.startIndex
            while let o = text.range(of: find.text, options: .caseInsensitive, range: at ..< text.endIndex) { total += 1; at = o.upperBound }
        }
        await target.web.call("mdApp.findAt(q, false, k, line, total)", ["q": find.text, "k": find.occurrence, "line": find.line, "total": total])
    }

    /// Edit → Search in folders: shows the sidebar and puts the caret in the search box.
    func focusTreeSearch() {
        guard !prefs.folders.isEmpty else { flash(L("SearchNoFolders")); return }
        prefs.sidebar = true
        search.focus()
    }
}

/// The results while the box has text, the tree otherwise (the tree keeps its open folders meanwhile).
struct SearchOrTree<Tree: View>: View {
    let doc: DocWindow
    @ObservedObject var search: SearchState
    @ObservedObject var prefs: Prefs
    let current: URL?
    @ViewBuilder let tree: () -> Tree

    var body: some View {
        if search.active { TreeSearchResults(doc: doc, search: search, prefs: prefs, current: current) } else { tree() }
    }
}
