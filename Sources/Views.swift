// Gryphmark: the window's content: toolbar, sidebar (files and contents), find bar, status line.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct NSHostingViewFor {
    let doc: DocWindow
    init(_ d: DocWindow) { doc = d }
    func make() -> NSView {
        let v = NSHostingView(rootView: RootView(doc: doc, model: doc.model, prefs: Prefs.shared))
        v.sizingOptions = []          // the window decides its size, not the content
        // With no sizing options the hosting view also clears the window's minimum size, so the
        // minimum is held by constraints (1.0.0 could be dragged down to a strip that cut it all).
        v.widthAnchor.constraint(greaterThanOrEqualToConstant: DocWindow.minContent.width).isActive = true
        v.heightAnchor.constraint(greaterThanOrEqualToConstant: DocWindow.minContent.height).isActive = true
        return v
    }
}

struct WebHost: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ v: WKWebView, context: Context) {}
}

struct RootView: View {
    let doc: DocWindow
    @ObservedObject var model: DocModel
    @ObservedObject var prefs: Prefs
    @StateObject private var drag = DragState()     // the sidebar divider while it is dragged
    @StateObject private var dragRight = DragState()   // the divider of Contents on the right of the text

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(doc: doc, prefs: prefs)
            Divider()
            GeometryReader { geo in
                // View → Layout: stacked (Files above Contents), columns (side by side in the sidebar) or right
                // (Contents on the right of the text). Each panel keeps its width (dragged, and remembered by each
                // instance); the document never gets narrower than 380, so a narrow window takes the room from them.
                let cols = prefs.sideLayout == "columns", right = prefs.sidebar && prefs.sideLayout == "right"
                let rightW = right ? min(dragRight.live ?? prefs.outlineWidthRight,
                                         max(Prefs.sidebarRange.lowerBound, geo.size.width - 380 - Prefs.sidebarRange.lowerBound - 2 * SplitHandle.thickness)) : 0
                HStack(spacing: 0) {
                    if prefs.sidebar {
                        let range = cols ? Prefs.columnsRange : Prefs.sidebarRange
                        let room = geo.size.width - 380 - SplitHandle.thickness - (right ? rightW + SplitHandle.thickness : 0)
                        let width = min(drag.live ?? (cols ? prefs.sidebarWidthColumns : prefs.sidebarWidth), max(range.lowerBound, room))
                        Sidebar(doc: doc, model: model, prefs: prefs, part: cols ? .columns : right ? .files : .stacked)
                            .frame(width: width).frame(maxHeight: .infinity)
                        SplitHandle(vertical: true) { moved in
                            if drag.from == nil { drag.from = width }
                            drag.live = cols ? Prefs.clampColumns(drag.from! + moved) : Prefs.clampWidth(drag.from! + moved)
                        } ended: {
                            if let w = drag.live { if cols { prefs.sidebarWidthColumns = w } else { prefs.sidebarWidth = w } }
                            drag.live = nil; drag.from = nil
                        }
                    }
                    VStack(spacing: 0) {
                        if model.findVisible { FindBar(doc: doc, model: model); Divider() }
                        WebHost(web: doc.web.view).frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        StatusLine(model: model, prefs: prefs)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if right {
                        SplitHandle(vertical: true, id: "rightDivider") { moved in
                            if dragRight.from == nil { dragRight.from = rightW }
                            dragRight.live = Prefs.clampWidth(dragRight.from! - moved)
                        } ended: {
                            if let w = dragRight.live { prefs.outlineWidthRight = w }
                            dragRight.live = nil; dragRight.from = nil
                        }
                        Sidebar(doc: doc, model: model, prefs: prefs, part: .outline).frame(width: rightW).frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(prefs.highlight)
        .id(prefs.lang)
    }
}

// MARK: dividers

/// What a divider keeps while it is dragged. A class and not @State: @State needs a macro plugin that only comes
/// with Xcode, and this app is built with the Command Line Tools (compilar.sh stops on @State).
final class DragState: ObservableObject {
    @Published var live: Double?       // the size shown while dragging, saved when the divider is let go
    @Published var from: Double?       // the size when the drag began
    @Published var hovering = false
}

/// A divider that is dragged to resize the panes on both sides of it: a 1-point line in a wider strip that takes
/// the mouse. `moved` gets the distance from where the drag began (in the window, so the moving divider does not
/// change it); `ended` is where the new size is saved.
struct SplitHandle: View {
    static let thickness: CGFloat = 5
    let vertical: Bool                    // true: a vertical line, dragged left and right
    var id: String? = nil                 // its accessibility name (the self-test finds it by this)
    let moved: (Double) -> Void
    let ended: () -> Void
    @StateObject private var hover = DragState()    // hover.hovering: the resize cursor is pushed

    var body: some View {
        ZStack {
            Color.clear
            Rectangle().fill(Color(nsColor: .separatorColor))
                .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
        }
        .frame(width: vertical ? Self.thickness : nil, height: vertical ? nil : Self.thickness)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside, !hover.hovering { (vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
            if !inside, hover.hovering { NSCursor.pop() }
            hover.hovering = inside
        }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { moved(Double(vertical ? $0.translation.width : $0.translation.height)) }
            .onEnded { _ in ended() })
        .accessibilityIdentifier(id ?? (vertical ? "sidebarDivider" : "outlineDivider"))
    }
}

// MARK: toolbar

struct ToolbarView: View {
    let doc: DocWindow
    @ObservedObject var prefs: Prefs

    private struct Tool { let symbol, tip: String; let action: () -> Void }

    private var off: Bool { prefs.readOnly || prefs.mode == "preview" }

    private var inline: [Tool] { [
        Tool(symbol: "bold", tip: L("Bold")) { doc.exec("bold") },
        Tool(symbol: "italic", tip: L("Italic")) { doc.exec("italic") },
        Tool(symbol: "strikethrough", tip: L("Strike")) { doc.exec("strike") },
        Tool(symbol: "chevron.left.forwardslash.chevron.right", tip: L("Code")) { doc.exec("code") },
    ] }
    private var lists: [Tool] { [
        Tool(symbol: "list.bullet", tip: L("Ul")) { doc.exec("bulletList") },
        Tool(symbol: "list.number", tip: L("Ol")) { doc.exec("orderedList") },
        Tool(symbol: "checklist", tip: L("Task")) { doc.exec("taskList") },
        Tool(symbol: "decrease.indent", tip: L("Outdent")) { doc.exec("outdent") },
        Tool(symbol: "increase.indent", tip: L("Indent")) { doc.exec("indent") },
    ] }
    private var blocks: [Tool] { [
        Tool(symbol: "text.quote", tip: L("Quote")) { doc.exec("blockQuote") },
        Tool(symbol: "curlybraces", tip: L("CodeBlock")) { doc.exec("codeBlock") },
        Tool(symbol: "tablecells", tip: L("Table")) { doc.insertTable() },
        Tool(symbol: "link", tip: L("Link")) { doc.insertLink() },
        Tool(symbol: "photo", tip: L("Image")) { doc.insertImage() },
        Tool(symbol: "minus", tip: L("Hr")) { doc.exec("hr") },
    ] }

    private func buttons(_ tools: [Tool]) -> some View {
        ForEach(tools, id: \.symbol) { t in
            Button(action: t.action) { Image(systemName: t.symbol).frame(width: 18, height: 18) }
                .buttonStyle(.borderless).help(t.tip).disabled(off)
        }
    }

    /// The groups that do not fit in a narrow window go into this menu.
    private func more(_ groups: [[Tool]]) -> some View {
        Menu {
            ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                if i > 0 { Divider() }
                ForEach(g, id: \.symbol) { t in Button(action: t.action) { Label(t.tip, systemImage: t.symbol) } }
            }
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().help(L("MoreTools")).disabled(off)
    }

    private var sep: some View { Divider().frame(height: 18) }

    var body: some View {
        HStack(spacing: 6) {
            Button { prefs.sidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless).help(L("Sidebar"))
            sep
            Menu {
                ForEach(1 ... 6, id: \.self) { n in
                    Button("H\(n)") { doc.exec("heading", ["level": n]) }
                }
                Button(L("Paragraph")) { doc.exec("heading", ["level": 0]) }
            } label: { Text("H").font(.system(size: 13, weight: .bold)) }
                .menuStyle(.borderlessButton).fixedSize().help(L("Heading"))
                .disabled(off)
            // The whole toolbar must fit the window: the widest arrangement that fits is used.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { buttons(inline); sep; buttons(lists); sep; buttons(blocks) }
                HStack(spacing: 6) { buttons(inline); sep; buttons(lists); more([blocks]) }
                HStack(spacing: 6) { buttons(inline); more([lists, blocks]) }
                HStack(spacing: 6) { more([inline, lists, blocks]) }
            }
            .frame(minWidth: 0, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 8)
            Toggle(isOn: Binding(get: { prefs.autoSave }, set: { DocWindow.setAutoSave($0) })) {
                Text(L("AutoSave")).font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.mini).fixedSize().help(L("TipAutoSave"))
            Picker("", selection: Binding(get: { prefs.readOnly }, set: { doc.setReadOnly($0) })) {
                Text(L("SegEdit")).tag(false).help(L("TipEdit"))
                Text(L("SegRead")).tag(true).help(L("TipRead"))
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().help(L("Lock"))
            Picker("", selection: Binding(get: { prefs.mode }, set: { doc.setMode($0) })) {
                Text(L("SegVisual")).tag("visual").help(L("TipVisual"))
                Text(L("SegSource")).tag("source").help(L("TipSource"))
                Text(L("SegPreview")).tag("preview").help(L("TipPreview"))
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().help(L("Mode"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: sidebar

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    var id: String { url.path }

    var children: [FileNode]? {
        guard isFolder else { return nil }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
        var out: [FileNode] = []
        for u in items {
            let dir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if dir {
                if FileNode.containsMarkdown(u, depth: 4) { out.append(FileNode(url: u, isFolder: true)) }
            } else if LinkPolicy.markdown.contains(u.pathExtension.lowercased()) && u.pathExtension.lowercased() != "txt" {
                out.append(FileNode(url: u, isFolder: false))
            }
        }
        return out.sorted { a, b in
            a.isFolder != b.isFolder ? a.isFolder : a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
    }

    /// Folders without any Markdown file inside are left out of the tree.
    static func containsMarkdown(_ dir: URL, depth: Int) -> Bool {
        guard depth > 0, let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return false }
        for case let u as URL in e {
            if e.level > depth { e.skipDescendants(); continue }
            let x = u.pathExtension.lowercased()
            if x == "md" || x == "markdown" || x == "mdown" || x == "mkd" { return true }
        }
        return false
    }
}

/// The Files tree: which folders are open, and a counter that Refresh bumps to read the disk again.
/// A class and not @State (see DragState).
final class TreeState: ObservableObject {
    @Published var open: Set<String> = []
    @Published var tick = 0
    private var revealed: String?     // the file last revealed: a folder closed by hand afterwards stays closed

    /// Opens every folder from the panel folder that holds the file down to it, once per file. Paths are compared
    /// with symbolic links resolved (/tmp and /private/tmp are the same folder), and the folders are named as the
    /// tree names them: the panel folder as it was added, plus the names below it.
    func reveal(_ file: URL?, roots: [String]) {
        guard let file else { return }
        let path = TreeState.canonical(file.path)
        guard path != revealed else { return }
        revealed = path
        let match = roots.map { r -> (String, String) in
            let root = r.count > 1 && r.hasSuffix("/") ? String(r.dropLast()) : r
            return (root, TreeState.canonical(root))
        }.filter { path.hasPrefix($0.1 + "/") }.max { $0.1.count < $1.1.count }
        guard let (root, canon) = match else { return }
        var dir = root
        for part in path.dropFirst(canon.count + 1).split(separator: "/").dropLast() {
            dir += "/" + part
            open.insert(dir)
        }
    }

    static func canonical(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
}

/// What a Sidebar shows: both panes stacked or side by side, or one of them (the layout "right" puts Contents on
/// the other side of the text).
enum SidebarPart { case stacked, columns, files, outline }

struct Sidebar: View {
    let doc: DocWindow
    @ObservedObject var model: DocModel
    @ObservedObject var prefs: Prefs
    var part: SidebarPart = .stacked
    @StateObject private var tree = TreeState()
    @StateObject private var drag = DragState()     // the divider between Files and Contents while it is dragged
    @ObservedObject private var ops = FileOps.shared

    var body: some View {
        switch part {
        case .files: files
        case .outline: outline
        case .columns: sideBySide
        case .stacked: stacked
        }
    }

    // Files | Contents; the divider between them is dragged, and each instance keeps the share.
    private var sideBySide: some View {
        GeometryReader { geo in
            let usable = max(1, Double(geo.size.width - SplitHandle.thickness))
            let share = drag.live ?? prefs.outlineShareColumns
            let outlineWidth = (usable * share).rounded()
            HStack(spacing: 0) {
                files.frame(width: usable - outlineWidth).clipped()
                SplitHandle(vertical: true, id: "panesDivider") { moved in
                    if drag.from == nil { drag.from = share }
                    drag.live = Prefs.clampShare(drag.from! - moved / usable)
                } ended: {
                    if let v = drag.live { prefs.outlineShareColumns = v }
                    drag.live = nil; drag.from = nil
                }
                outline.frame(width: outlineWidth).clipped()
            }
        }
    }

    private var stacked: some View {
        // Files above, Contents below; the divider between them is dragged, and each instance keeps the share.
        GeometryReader { geo in
            let usable = max(1, Double(geo.size.height - SplitHandle.thickness))
            let share = drag.live ?? prefs.outlineShare
            let outlineHeight = (usable * share).rounded()
            VStack(spacing: 0) {
                files.frame(height: usable - outlineHeight, alignment: .top).clipped()
                SplitHandle(vertical: false) { moved in
                    if drag.from == nil { drag.from = share }
                    drag.live = Prefs.clampShare(drag.from! - moved / usable)
                } ended: {
                    if let v = drag.live { prefs.outlineShare = v }
                    drag.live = nil; drag.from = nil
                }
                outline.frame(height: outlineHeight, alignment: .top).clipped()
            }
        }
    }

    private var files: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("FilesTitle")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                // renames and moves of the tree: undo, redo, and the padlock that allows dragging (FileOps)
                Button { Task { await ops.undo(doc: doc) } } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).disabled(ops.undoStack.isEmpty)
                    .help(ops.undoStack.last.map { L("FileUndoTip", FileOps.describe($0)) } ?? L("FileUndoNone"))
                Button { Task { await ops.redo(doc: doc) } } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(.borderless).disabled(ops.redoStack.isEmpty)
                    .help(ops.redoStack.last.map { L("FileRedoTip", FileOps.describe($0)) } ?? L("FileRedoNone"))
                Button { prefs.treeLocked.toggle() } label: { Image(systemName: prefs.treeLocked ? "lock" : "lock.open") }
                    .buttonStyle(.borderless).help(L(prefs.treeLocked ? "TreeLockedTip" : "TreeUnlockedTip"))
                    .accessibilityIdentifier("treeLock")
                Button { tree.open = [] } label: { Image(systemName: "chevron.up.chevron.down") }
                    .buttonStyle(.borderless).help(L("CollapseAll"))
                Button { tree.tick += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(L("Refresh"))
                Button { (NSApp.delegate as? AppDelegate)?.pickFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.borderless).help(L("FolderAdd"))
                FolderOptionsMenu(prefs: prefs, tree: tree)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            if prefs.folders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("FilesEmpty")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Button(L("FilesOpenBtn")) { (NSApp.delegate as? AppDelegate)?.pickFolder() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(prefs.orderedFolders, id: \.self) { f in
                            let root = FileNode(url: URL(fileURLWithPath: f), isFolder: true)
                            Section {
                                ForEach(root.children ?? []) { node in
                                    FileTreeNode(doc: doc, node: node, current: model.path, highlight: prefs.highlight, tree: tree)
                                }
                            } header: {
                                FolderHeader(doc: doc, dir: f, prefs: prefs, tree: tree)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .id(tree.tick)
                    // The open file is shown: its folders open and the list scrolls to it (as on Windows).
                    .onAppear { show(model.path, proxy) }
                    .onChange(of: model.path) { _, path in show(path, proxy) }
                    .onChange(of: prefs.folders) { _, _ in show(model.path, proxy) }
                    .onChange(of: ops.generation) { _, _ in tree.tick += 1; show(model.path, proxy) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func show(_ path: URL?, _ proxy: ScrollViewProxy) {
        tree.reveal(path, roots: prefs.folders)
        guard let id = path.map({ TreeState.canonical($0.path) }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .center) }
    }

    private var outline: some View {
        VStack(spacing: 0) {
            Text(L("OutlineTitle")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
            if model.outline.isEmpty {
                Text(L("OutlineEmpty")).font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(Array(model.outline.enumerated()), id: \.offset) { i, h in
                        Button { Task { await doc.web.call("mdApp.scrollToHeading(i)", ["i": i]) } } label: {
                            Text(h.text).lineLimit(1).fontWeight(h.level == 1 ? .semibold : .regular)
                                .opacity(h.level >= 3 ? 0.75 : 1)
                                .padding(.leading, CGFloat(h.level - 1) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).help(h.text)
                    }
                }
                .listStyle(.sidebar)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A menu entry with a check mark when `on`.
func checkItem(_ title: String, _ on: Bool, image: NSImage? = nil, _ run: @escaping () -> Void) -> some View {
    Toggle(isOn: Binding(get: { on }, set: { _ in run() })) {
        if let image { Label { Text(title) } icon: { Image(nsImage: image) } } else { Text(title) }
    }
}

/// A small square of a folder colour for the Colour menu (not a template image, so the menu keeps its colour).
func swatch(_ hue: Double, dark: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
        NSColor(Prefs.color(hue, 0.6, dark ? 0.45 : 0.75)).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5).fill()
        return true
    }
    img.isTemplate = false
    return img
}

/// The heading of an open folder in the Files panel: its colour, a pin when it is pinned, and its right-click
/// menu (pin, close, colour, move, dedicated instance, Finder, path, collapse, refresh), as on Windows.
struct FolderHeader: View {
    let doc: DocWindow
    let dir: String
    @ObservedObject var prefs: Prefs
    @ObservedObject var tree: TreeState

    var body: some View {
        let url = URL(fileURLWithPath: dir)
        let tint = prefs.folderTint(dir)
        let exists = FileManager.default.fileExists(atPath: dir)
        let manual = prefs.folderSort == "opened"
        let i = prefs.folders.firstIndex(of: dir) ?? -1
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(tint?.edge ?? Color.secondary)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(exists && tint != nil ? Color.primary : Color.secondary)
            if !exists { Text(L("FolderUnavailable")).font(.system(size: 10)).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            if prefs.isPinned(dir) {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary).help(L("FolderPinnedTip"))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(tint?.fill ?? Color.clear))
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], isTargeted: nil) { FileOps.shared.drop($0, into: url, doc: doc) }
        .contextMenu {
            Button(L(prefs.isPinned(dir) ? "FolderUnpin" : "FolderPin")) { prefs.togglePin(dir) }
            Button(L("FolderCloseOne")) { prefs.closeFolder(dir) }
            Menu(L("FolderColor")) {
                checkItem(L("FolderColorAuto"), prefs.folderColorMap[dir] == nil) { prefs.folderColorMap[dir] = nil }
                Divider()
                ForEach(Prefs.folderHues, id: \.hue) { c in
                    checkItem(prefs.lang == "es" ? c.es : c.en, prefs.folderColorMap[dir] == c.hue, image: swatch(c.hue, dark: prefs.dark)) {
                        prefs.folderColorMap[dir] = c.hue
                    }
                }
            }
            .disabled(prefs.folderColors == "none")
            Button(L("FolderUp")) { prefs.moveFolder(dir, by: -1) }.disabled(!manual || i <= 0)
            Button(L("FolderDown")) { prefs.moveFolder(dir, by: 1) }.disabled(!manual || i < 0 || i >= prefs.folders.count - 1)
            Divider()
            Button(L("OpenDedicated")) { (NSApp.delegate as? AppDelegate)?.openDedicated(url, from: doc) }.disabled(!exists)
            Button(L("OpenFolder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(!exists)
            Button(L("CopyPath")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(dir, forType: .string) }
            Divider()
            Button(L("CollapseAll")) { tree.open = [] }
            Button(L("Refresh")) { tree.tick += 1 }
            Divider()
            Button(L("FolderCloseAll")) { prefs.folders = [] }
        }
    }
}

/// The ⋯ button of the Files panel: order of the folders, their colours, what opens at start, and folder-wide actions.
struct FolderOptionsMenu: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var tree: TreeState

    var body: some View {
        Menu {
            Section(L("FolderSortTitle")) {
                ForEach([("opened", "FolderSortOpened"), ("az", "FolderSortAz"), ("za", "FolderSortZa"), ("modified", "FolderSortModified")], id: \.0) { k, t in
                    checkItem(L(t), prefs.folderSort == k) { prefs.folderSort = k }
                }
            }
            Section(L("FolderColorsTitle")) {
                ForEach([("theme", "FolderColorsTheme"), ("multi", "FolderColorsMulti"), ("none", "FolderColorsNone")], id: \.0) { k, t in
                    checkItem(L(t), prefs.folderColors == k) { prefs.folderColors = k }
                }
            }
            Section(L("StartupTitle")) {
                ForEach([("restore", "StartupRestore"), ("clean", "StartupClean"), ("pinned", "StartupPinned")], id: \.0) { k, t in
                    checkItem(L(t), prefs.startupFolders == k) { prefs.startupFolders = k }
                }
            }
            Divider()
            Button(L("FolderAdd")) { (NSApp.delegate as? AppDelegate)?.pickFolder() }
            Button(L("CollapseAll")) { tree.open = [] }
            Button(L("FolderCloseAll")) { prefs.folders = [] }.disabled(prefs.folders.isEmpty)
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("FolderOptions"))
    }
}

/// A file, or a folder that opens and closes; the folders that are open are kept in TreeState.
struct FileTreeNode: View {
    let doc: DocWindow
    let node: FileNode
    let current: URL?
    let highlight: Color
    @ObservedObject var tree: TreeState

    var body: some View {
        if node.isFolder {
            DisclosureGroup(isExpanded: Binding(get: { tree.open.contains(node.id) },
                                                set: { if $0 { tree.open.insert(node.id) } else { tree.open.remove(node.id) } })) {
                ForEach(node.children ?? []) { FileTreeNode(doc: doc, node: $0, current: current, highlight: highlight, tree: tree) }
            } label: {
                FileRow(doc: doc, node: node, current: current, highlight: highlight, tree: tree)
            }
        } else {
            FileRow(doc: doc, node: node, current: current, highlight: highlight, tree: tree).id(TreeState.canonical(node.url.path))
        }
    }
}

struct FileRow: View {
    let doc: DocWindow
    let node: FileNode
    let current: URL?
    let highlight: Color
    @ObservedObject var tree: TreeState
    @ObservedObject private var prefs = Prefs.shared
    @StateObject private var drop = DragState()      // hovering: something of the tree is dragged over this row

    var body: some View {
        // The open file stands out as a selected row does: a filled band in the highlight colour.
        let isCurrent = !node.isFolder && current.map { TreeState.canonical($0.path) == TreeState.canonical(node.url.path) } == true
        Label(node.url.lastPathComponent, systemImage: node.isFolder ? "folder" : "doc.text")
            .fontWeight(isCurrent ? .semibold : .regular)
            .padding(.vertical, 2).padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? highlight.opacity(0.3) : drop.hovering ? highlight.opacity(0.18) : .clear))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .contentShape(Rectangle())
            .onTapGesture { if !node.isFolder { (NSApp.delegate as? AppDelegate)?.open(node.url, from: doc) } }
            .modifier(TreeDragSource(url: node.url, enabled: !prefs.treeLocked && !FileOps.isRoot(node.url)))
            // a drop goes into this folder, or into the folder of this file
            .onDrop(of: [.plainText], isTargeted: Binding(get: { drop.hovering }, set: { drop.hovering = $0 && !prefs.treeLocked })) {
                FileOps.shared.drop($0, into: node.isFolder ? node.url : node.url.deletingLastPathComponent(), doc: doc)
            }
            .contextMenu {
                if !node.isFolder {
                    Button(L("FileOpen")) { (NSApp.delegate as? AppDelegate)?.open(node.url, from: doc) }
                    Button(L("OpenNewWindow")) { (NSApp.delegate as? AppDelegate)?.open(node.url, from: nil) }
                }
                Button(L("OpenFolder")) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                Button(L("OpenDedicated")) { (NSApp.delegate as? AppDelegate)?.openDedicated(node.url, from: doc) }
                Button(L("CopyPath")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.url.path, forType: .string)
                }
                if !FileOps.isRoot(node.url) { Button(L("Rename")) { FileOps.shared.rename(node.url, doc: doc) } }
                if !node.isFolder {
                    Divider()
                    Button(L("ConvertTxt")) { (NSApp.delegate as? AppDelegate)?.convertToText(node.url, from: doc) }
                }
                Divider()
                Button(L("CollapseAll")) { tree.open = [] }
                Button(L("Refresh")) { tree.tick += 1 }
            }
    }
}

/// With the tree unlocked a row can be dragged; what it carries is FileOps.dragPrefix and its path.
struct TreeDragSource: ViewModifier {
    let url: URL
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.onDrag { NSItemProvider(object: (FileOps.dragPrefix + url.path) as NSString) } } else { content }
    }
}

// MARK: find bar

struct FindBar: View {
    let doc: DocWindow
    @ObservedObject var model: DocModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField(L("FindPlaceholder"), text: $model.findQuery)
                    .textFieldStyle(.roundedBorder).frame(width: 260)
                    .onSubmit { doc.find(step: 1) }
                    .onChange(of: model.findQuery) { _, _ in doc.find(step: 0) }
                Toggle(L("MatchCase"), isOn: $model.findCase).onChange(of: model.findCase) { _, _ in doc.find(step: 0) }
                Button { doc.find(step: -1) } label: { Image(systemName: "chevron.up") }.help(L("Prev"))
                Button { doc.find(step: 1) } label: { Image(systemName: "chevron.down") }.help(L("Next"))
                Text(model.findInfo).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { doc.hideFind() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).help(L("Close"))
                    .keyboardShortcut(.cancelAction)
            }
            if model.replaceVisible {
                HStack(spacing: 8) {
                    TextField(L("ReplacePlaceholder"), text: $model.replaceText).textFieldStyle(.roundedBorder).frame(width: 260)
                    Button(L("ReplaceOne")) { doc.replaceOne() }.disabled(Prefs.shared.readOnly)
                    Button(L("ReplaceAll")) { doc.replaceAll() }.disabled(Prefs.shared.readOnly)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}

// MARK: status line

struct StatusLine: View {
    @ObservedObject var model: DocModel
    @ObservedObject var prefs: Prefs

    var body: some View {
        HStack(spacing: 14) {
            Text(L("Words", model.words))
            if model.path != nil { Text("UTF-8" + (model.bom ? " BOM" : "") + " · " + (model.crlf ? "CRLF" : "LF")) }
            Text(model.dirty ? L("Modified") : "").foregroundStyle(prefs.highlight)
            if !model.flash.isEmpty { Text(model.flash).foregroundStyle(prefs.highlight) }
            Spacer()
            Button { (NSApp.keyWindow?.windowController as? DocWindow)?.setZoom(prefs.zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless).help(L("ZoomOut"))
            // the zoom bar, as on Windows: 50 % to 300 % in steps of 10
            Slider(value: Binding(get: { prefs.zoom }, set: { z in
                if let d = DocWindow.all.first(where: { $0.model === model }) { d.setZoom(z) } else { prefs.zoom = z }
            }), in: 0.5...3, step: 0.1)
                .controlSize(.mini).frame(width: 110).help(L("ZoomSliderTip"))
            Button("\(Int((prefs.zoom * 100).rounded())) %") { (NSApp.keyWindow?.windowController as? DocWindow)?.setZoom(1) }
                .buttonStyle(.borderless).help(L("ZoomReset"))
            Button { (NSApp.keyWindow?.windowController as? DocWindow)?.setZoom(prefs.zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless).help(L("ZoomSliderTip"))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
    }
}
