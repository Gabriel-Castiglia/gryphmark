// Gryphmark: start-up, menus, opening files and folders, recovery, updates.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// One window per document. The menus are built here in the app's language (English or
// Spanish, switched at run time). Besides opening files, the program answers to:
//   --self-test           checks the page, the link rules, saving and live reload (SelfTest.swift)
//   --screenshot FILE     draws a window into a PNG and quits, for the manuals; with
//                         --view main|theme|about, --lang en|es, --theme light|dark,
//                         --accent KEY, --mode visual|source|preview, --open FILE
// Those two never read or write the preferences.

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

final class ClosureItem: NSMenuItem {
    private let run: () -> Void
    var isOn: () -> Bool = { false }
    init(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = .command, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = mods
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

final class MenuStates: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for case let i as ClosureItem in menu.items { i.state = i.isOn() ? .on : .off }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let prefs = Prefs.shared
    private let states = MenuStates()
    private var bag: Set<AnyCancellable> = []
    private var themeWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var appearanceWatch: NSKeyValueObservation?
    private var launchFiles: [URL] = []
    private var launched = false

    var current: DocWindow? {
        (NSApp.keyWindow?.windowController as? DocWindow) ?? (NSApp.mainWindow?.windowController as? DocWindow) ?? DocWindow.all.last
    }

    func argument(after flag: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        if launched { urls.forEach { open($0, from: nil) } } else { launchFiles += urls }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let shot = argument(after: "--screenshot")
        let selfTest = CommandLine.arguments.contains("--self-test")
        prefs.persist = shot == nil && !selfTest
        prefs.load()
        if shot != nil {
            if let l = argument(after: "--lang") { prefs.lang = l == "es" ? "es" : "en" }
            if let t = argument(after: "--theme") { prefs.theme = t }
            if let a = argument(after: "--accent") { prefs.accent = a }
            if let m = argument(after: "--mode") { prefs.mode = m }
            prefs.sidebar = true
        }
        prefs.applyAppearance()
        prefs.applyDockIcon()
        buildMenus()
        prefs.$lang.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.buildMenus()
                for d in DocWindow.all { Task { await d.applyLanguage() } }
                self?.themeWindow?.title = L("ThemeMenu").replacingOccurrences(of: "…", with: "")
                self?.aboutWindow?.title = L("About")
            }
        }.store(in: &bag)
        prefs.$dark.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { _ in
            DispatchQueue.main.async { for d in DocWindow.all { Task { await d.applyTheme() } } }
        }.store(in: &bag)
        appearanceWatch = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.prefs.refreshDark() }
        }
        launched = true

        if selfTest { SelfTest.start(); return }
        if let shot { screenshot(to: shot); return }

        let files = launchFiles
        if files.isEmpty {
            let d = newWindow()
            if !prefs.sampleShown { prefs.sampleShown = true; openSample(in: d) }
        } else {
            files.forEach { open($0, from: nil) }
        }
        offerRecovery()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = DocWindow.all.filter { $0.model.dirty }
        guard !dirty.isEmpty else { return .terminateNow }
        Task { @MainActor in
            for d in dirty {
                d.window?.makeKeyAndOrderFront(nil)
                if !(await d.confirmDiscard()) { NSApp.reply(toApplicationShouldTerminate: false); return }
                d.model.dirty = false
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: windows and files

    @discardableResult
    func newWindow() -> DocWindow {
        let d = DocWindow()
        if let w = d.window {
            if DocWindow.all.count == 1 && !w.setFrameUsingName("Document") { w.center() }
            else if let prev = DocWindow.all.dropLast().last?.window {
                w.setFrame(prev.frame.offsetBy(dx: 26, dy: -26), display: false)
            }
            w.setFrameAutosaveName(DocWindow.all.count == 1 ? "Document" : "")
        }
        d.showWindow(nil)
        NSApp.activate()
        return d
    }

    /// Opens a file: brings its window forward if it is open, else uses `from` (or an empty
    /// untitled window) or a new one.
    func open(_ url: URL, from doc: DocWindow?) {
        let url = url.standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            addFolder(url); return
        }
        if let open = DocWindow.all.first(where: { $0.model.path == url }) { open.window?.makeKeyAndOrderFront(nil); return }
        let target = doc ?? DocWindow.all.first { $0.isEmptyUntitled } ?? newWindow()
        target.open(url)
        target.window?.makeKeyAndOrderFront(nil)
    }

    func openPanel() {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["md", "markdown", "mdown", "mkd", "txt"].compactMap { UTType(filenameExtension: $0) }
        p.allowsMultipleSelection = true
        if let d = current?.model.path?.deletingLastPathComponent() { p.directoryURL = d }
        guard p.runModal() == .OK else { return }
        p.urls.forEach { open($0, from: nil) }
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        guard p.runModal() == .OK, let u = p.url else { return }
        addFolder(u)
    }

    func addFolder(_ u: URL) {
        if !prefs.folders.contains(u.path) { prefs.folders.append(u.path) }
        prefs.sidebar = true
    }

    static var samplePath: URL? {
        Bundle.main.url(forResource: "sample_\(Prefs.shared.lang)", withExtension: "md", subdirectory: "samples")
            ?? Bundle.main.url(forResource: "sample_en", withExtension: "md", subdirectory: "samples")
    }

    /// The sample opens as an untitled copy, so the installed file is never overwritten.
    func openSample(in doc: DocWindow? = nil) {
        guard let p = AppDelegate.samplePath, let text = try? String(contentsOf: p, encoding: .utf8) else { return }
        let d = doc ?? (current?.isEmptyUntitled == true ? current! : newWindow())
        let go = { Task { @MainActor in await d.loadText(text, sample: true) } }
        if d.model.ready { _ = go() } else { d.onReady = { _ = go() } }
    }

    func openManual() {
        let name = prefs.lang == "es" ? "Gryphmark-manual-es" : "Gryphmark-manual-en"
        if let u = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "docs") { NSWorkspace.shared.open(u) }
    }

    func showTheme() {
        if themeWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 608, height: 440), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ThemeView(prefs: prefs))
            w.center()
            themeWindow = w
        }
        themeWindow?.title = L("ThemeMenu").replacingOccurrences(of: "…", with: "")
        themeWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        if aboutWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 520), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AboutView(prefs: prefs))
            w.center()
            aboutWindow = w
        }
        aboutWindow?.title = L("About")
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: recovery and updates

    /// Drafts left by a session that ended without saving are offered once, at start.
    func offerRecovery() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: DocWindow.recoveryFolder, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = d["text"] as? String else { try? fm.removeItem(at: f); continue }
            let path = (d["path"] as? String) ?? ""
            let a = NSAlert()
            a.messageText = L("Recover", path.isEmpty ? L("Untitled") : (path as NSString).lastPathComponent, (d["time"] as? String) ?? "")
            a.addButton(withTitle: L("RecoverBtn"))
            a.addButton(withTitle: L("DiscardBtn"))
            let take = a.runModal() == .alertFirstButtonReturn
            try? fm.removeItem(at: f)
            guard take else { continue }
            let doc = DocWindow.all.first { $0.isEmptyUntitled } ?? newWindow()
            let go = {
                Task { @MainActor in
                    if !path.isEmpty, fm.fileExists(atPath: path) { await doc.load(URL(fileURLWithPath: path)) }
                    await doc.web.call("mdApp.load(t, b)", ["t": text, "b": doc.model.path == nil ? NSNull() : Schemes.docBase])
                    doc.model.dirty = true
                    doc.updateTitle()
                    doc.flash(L("Recovered"))
                }
            }
            if doc.model.ready { _ = go() } else { doc.onReady = { _ = go() } }
        }
    }

    func checkUpdates() {
        let url = URL(string: "https://api.github.com/repos/\(appRepo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("Gryphmark/\(appVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, err in
            let tag = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["tag_name"] as? String
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "Gryphmark"
                guard let tag else {
                    a.informativeText = L("UpdateError", err?.localizedDescription ?? "")
                    a.runModal(); return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if latest.compare(appVersion, options: .numeric) == .orderedDescending {
                    a.informativeText = L("UpdateAvailable", latest, appVersion)
                    a.addButton(withTitle: L("Download"))
                    a.addButton(withTitle: L("Later"))
                    if a.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "https://github.com/\(appRepo)/releases/latest")!)
                    }
                } else {
                    a.informativeText = L("UpToDate", appVersion)
                    a.runModal()
                }
            }
        }.resume()
    }

    // MARK: menus

    private func top(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.delegate = states
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    private func item(_ t: String, key: String = "", mods: NSEvent.ModifierFlags = .command,
                      on: @escaping () -> Bool = { false }, _ run: @escaping () -> Void) -> ClosureItem {
        let i = ClosureItem(t, key: key, mods: mods, run)
        i.isOn = on
        return i
    }

    private func doc(_ f: @escaping (DocWindow) -> Void) -> () -> Void { { [weak self] in if let d = self?.current { f(d) } } }

    private func send(_ sel: Selector) -> () -> Void { { _ = NSApp.sendAction(sel, to: nil, from: nil) } }

    func buildMenus() {
        let bar = NSMenu()
        bar.addItem(top("Gryphmark", [
            item(L("About")) { [weak self] in self?.showAbout() },
            item(L("CheckUpdates")) { [weak self] in self?.checkUpdates() },
            .separator(),
            item(L("ThemeMenu"), key: ",") { [weak self] in self?.showTheme() },
            .separator(),
            item(L("Hide"), key: "h") { NSApp.hide(nil) },
            item(L("HideOthers"), key: "h", mods: [.command, .option]) { NSApp.hideOtherApplications(nil) },
            item(L("ShowAll")) { NSApp.unhideAllApplications(nil) },
            .separator(),
            item(L("Quit"), key: "q") { NSApp.terminate(nil) },
        ]))

        let recent = NSMenu(title: L("Recent"))
        recent.delegate = states
        let recentItem = NSMenuItem(title: L("Recent"), action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        if prefs.recent.isEmpty {
            let e = NSMenuItem(title: L("RecentEmpty"), action: nil, keyEquivalent: ""); e.isEnabled = false
            recent.addItem(e)
        } else {
            for p in prefs.recent {
                recent.addItem(item((p as NSString).lastPathComponent) { [weak self] in self?.open(URL(fileURLWithPath: p), from: nil) })
            }
            recent.addItem(.separator())
            recent.addItem(item(L("RecentClear")) { [weak self] in self?.prefs.recent = []; self?.buildMenus() })
        }

        bar.addItem(top(L("File"), [
            item(L("New"), key: "n") { [weak self] in self?.newWindow() },
            item(L("Open"), key: "o") { [weak self] in self?.openPanel() },
            recentItem,
            item(L("OpenDir"), key: "o", mods: [.command, .shift]) { [weak self] in self?.pickFolder() },
            item(L("CloseDir")) { [weak self] in self?.prefs.folders = [] },
            .separator(),
            item(L("CloseWindow"), key: "w") { NSApp.keyWindow?.performClose(nil) },
            item(L("Save"), key: "s", doc { d in Task { await d.save(as: false) } }),
            item(L("SaveAs"), key: "s", mods: [.command, .shift], doc { d in Task { await d.save(as: true) } }),
            item(L("ExportHtml"), key: "e", doc { $0.exportHtml() }),
            item(L("Print"), key: "p", doc { $0.command("print") }),
            .separator(),
            item(L("OpenFolder"), doc { d in if let p = d.model.path { NSWorkspace.shared.activateFileViewerSelecting([p]) } }),
        ]))

        bar.addItem(top(L("Edit"), [
            item(L("Undo"), key: "z", doc { $0.exec("undo") }),
            item(L("Redo"), key: "z", mods: [.command, .shift], doc { $0.exec("redo") }),
            .separator(),
            item(L("Cut"), key: "x", send(#selector(NSText.cut(_:)))),
            item(L("Copy"), key: "c", send(#selector(NSText.copy(_:)))),
            item(L("Paste"), key: "v", send(#selector(NSText.paste(_:)))),
            item(L("SelectAll"), key: "a", send(#selector(NSText.selectAll(_:)))),
            .separator(),
            item(L("Find"), key: "f", doc { $0.showFind(replace: false) }),
            item(L("Replace"), key: "f", mods: [.command, .option], doc { $0.showFind(replace: true) }),
            item(L("FindNext"), key: "g", doc { $0.find(step: 1) }),
            item(L("Prev").components(separatedBy: " (")[0], key: "g", mods: [.command, .shift], doc { $0.find(step: -1) }),
            .separator(),
            item(L("ReadOnly"), key: "l", mods: [.command, .shift], on: { [weak self] in self?.prefs.readOnly == true },
                 doc { $0.setReadOnly(!Prefs.shared.readOnly) }),
            item(L("Spell"), on: { [weak self] in self?.prefs.spell == true }) { [weak self] in
                guard let self else { return }
                self.prefs.spell.toggle()
                for d in DocWindow.all { Task { await d.applySpell() } }
            },
        ]))

        let headings: [NSMenuItem] = (1 ... 6).map { n in item("H\(n)", key: "\(n)", mods: [.command, .option], doc { $0.exec("heading", ["level": n]) }) }
            + [item(L("Paragraph"), key: "0", mods: [.command, .option], doc { $0.exec("heading", ["level": 0]) })]
        let headingItem = NSMenuItem(title: L("Heading"), action: nil, keyEquivalent: "")
        let hm = NSMenu(title: L("Heading")); headings.forEach(hm.addItem); headingItem.submenu = hm
        bar.addItem(top(L("Format"), [
            item(L("Bold"), key: "b", doc { $0.exec("bold") }),
            item(L("Italic"), key: "i", doc { $0.exec("italic") }),
            item(L("Strike"), key: "x", mods: [.command, .shift], doc { $0.exec("strike") }),
            item(L("Code"), key: "k", mods: [.command, .shift], doc { $0.exec("code") }),
            headingItem,
            .separator(),
            item(L("Quote"), doc { $0.exec("blockQuote") }),
            item(L("Ul"), doc { $0.exec("bulletList") }),
            item(L("Ol"), doc { $0.exec("orderedList") }),
            item(L("Task"), doc { $0.exec("taskList") }),
            item(L("CodeBlock"), doc { $0.exec("codeBlock") }),
            item(L("Hr"), doc { $0.exec("hr") }),
            .separator(),
            item(L("Table"), doc { $0.insertTable() }),
            item(L("Link"), key: "k", doc { $0.insertLink() }),
            item(L("Image"), doc { $0.insertImage() }),
        ]))

        bar.addItem(top(L("View"), [
            item(L("ModeVisual"), key: "1", on: { [weak self] in self?.prefs.mode == "visual" }, doc { $0.setMode("visual") }),
            item(L("ModeSource"), key: "2", on: { [weak self] in self?.prefs.mode == "source" }, doc { $0.setMode("source") }),
            item(L("ModePreview"), key: "3", on: { [weak self] in self?.prefs.mode == "preview" }, doc { $0.setMode("preview") }),
            .separator(),
            item(L("Sidebar"), key: "e", mods: [.command, .shift], on: { [weak self] in self?.prefs.sidebar == true }) { [weak self] in
                self?.prefs.sidebar.toggle()
            },
            .separator(),
            item(L("ZoomIn"), key: "+", doc { $0.setZoom(Prefs.shared.zoom + 0.1) }),
            item(L("ZoomOut"), key: "-", doc { $0.setZoom(Prefs.shared.zoom - 0.1) }),
            item(L("ZoomReset"), key: "0", doc { $0.setZoom(1) }),
            .separator(),
            item(L("ThemeMenu")) { [weak self] in self?.showTheme() },
        ]))

        bar.addItem(top(L("Language"), [
            item("English", on: { [weak self] in self?.prefs.lang == "en" }) { [weak self] in self?.prefs.lang = "en" },
            item("Español", on: { [weak self] in self?.prefs.lang == "es" }) { [weak self] in self?.prefs.lang = "es" },
        ]))

        let window = top(L("Window"), [
            item(L("Minimize"), key: "m") { NSApp.keyWindow?.miniaturize(nil) },
            item(L("ZoomWindow")) { NSApp.keyWindow?.zoom(nil) },
        ])
        bar.addItem(window)
        let help = top(L("Help"), [
            item(L("Manual"), key: "?") { [weak self] in self?.openManual() },
            item(L("Guide")) {
                let page = Prefs.shared.lang == "es" ? "es" : "en"
                NSWorkspace.shared.open(URL(string: "https://docs.github.com/\(page)/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax")!)
            },
            item(L("Sample")) { [weak self] in self?.openSample() },
        ])
        bar.addItem(help)
        NSApp.mainMenu = bar
        NSApp.windowsMenu = window.submenu
        NSApp.helpMenu = help.submenu
    }

    // MARK: screenshots

    private func screenshot(to path: String) {
        let view = argument(after: "--view") ?? "main"
        let d = newWindow()
        d.window?.setContentSize(NSSize(width: 1180, height: 760))
        d.window?.center()
        let file = argument(after: "--open").map { URL(fileURLWithPath: $0) }
        d.onReady = { [weak self] in
            if let file { d.open(file) } else { self?.openSample(in: d) }
            var target: NSWindow? = d.window
            if view == "theme" { self?.showTheme(); target = self?.themeWindow }
            if view == "about" { self?.showAbout(); target = self?.aboutWindow }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                Task { @MainActor in
                    var ok = false
                    if let t = target { ok = await AppDelegate.savePicture(of: t, web: t === d.window ? d.web.view : nil, to: path) }
                    FileHandle.standardError.write(Data((ok ? "screenshot saved: \(path)\n" : "screenshot failed\n").utf8))
                    exit(ok ? 0 : 1)
                }
            }
        }
    }

    /// The window as drawn by AppKit, with the web page's own snapshot laid where the page is
    /// (a web view does not draw into an AppKit cache).
    @MainActor
    static func savePicture(of window: NSWindow, web: WKWebView?, to path: String) async -> Bool {
        guard let root = window.contentView?.superview ?? window.contentView,
              let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return false }
        root.cacheDisplay(in: root.bounds, to: rep)
        if let web, let shot = try? await web.takeSnapshot(configuration: nil) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            shot.draw(in: web.convert(web.bounds, to: root))
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
