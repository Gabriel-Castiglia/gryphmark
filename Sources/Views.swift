// Gryphmark: the window's content: toolbar, sidebar (files and contents), find bar, status line.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import SwiftUI
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

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(doc: doc, prefs: prefs)
            Divider()
            HSplitView {
                if prefs.sidebar {
                    Sidebar(doc: doc, model: model, prefs: prefs).frame(minWidth: 240, idealWidth: 240, maxWidth: 420, maxHeight: .infinity)
                }
                VStack(spacing: 0) {
                    if model.findVisible { FindBar(doc: doc, model: model); Divider() }
                    WebHost(web: doc.web.view).frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    StatusLine(model: model, prefs: prefs)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)          // the document takes the room a wider window adds, not the sidebar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(prefs.highlight)
        .id(prefs.lang)
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

final class TreeRefresh: ObservableObject { @Published var tick = 0 }

struct Sidebar: View {
    let doc: DocWindow
    @ObservedObject var model: DocModel
    @ObservedObject var prefs: Prefs
    @StateObject private var refresh = TreeRefresh()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("FilesTitle")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { refresh.tick += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(L("Refresh"))
                Button { (NSApp.delegate as? AppDelegate)?.pickFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(.borderless).help(L("FolderAdd"))
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
                List {
                    ForEach(prefs.folders, id: \.self) { f in
                        let root = FileNode(url: URL(fileURLWithPath: f), isFolder: true)
                        Section {
                            OutlineGroup(root.children ?? [], children: \.children) { node in
                                FileRow(doc: doc, node: node, current: model.path)
                            }
                        } header: {
                            Text(root.url.lastPathComponent).foregroundStyle(prefs.highlight)
                                .contextMenu {
                                    Button(L("OpenFolder")) { NSWorkspace.shared.activateFileViewerSelecting([root.url]) }
                                    Button(L("FolderCloseOne")) { prefs.folders.removeAll { $0 == f } }
                                    Button(L("FolderCloseAll")) { prefs.folders = [] }
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
                .id(refresh.tick)
            }
            Divider()
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
                .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct FileRow: View {
    let doc: DocWindow
    let node: FileNode
    let current: URL?

    var body: some View {
        let isCurrent = node.url.standardizedFileURL == current?.standardizedFileURL
        Label(node.url.lastPathComponent, systemImage: node.isFolder ? "folder" : "doc.text")
            .fontWeight(isCurrent ? .semibold : .regular)
            .contentShape(Rectangle())
            .onTapGesture { if !node.isFolder { (NSApp.delegate as? AppDelegate)?.open(node.url, from: doc) } }
            .contextMenu {
                if !node.isFolder {
                    Button(L("FileOpen")) { (NSApp.delegate as? AppDelegate)?.open(node.url, from: doc) }
                    Button(L("OpenNewWindow")) { (NSApp.delegate as? AppDelegate)?.open(node.url, from: nil) }
                }
                Button(L("OpenFolder")) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                Button(L("CopyPath")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(node.url.path, forType: .string)
                }
            }
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
