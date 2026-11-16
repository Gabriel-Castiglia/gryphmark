// Gryphmark: renaming and moving files and folders from the Files panel, with undo and redo (as on Windows).
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 16, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// Everything happens on disk. Right-click → Rename… renames a file or folder; with the tree unlocked (the padlock
// in the panel header) files and folders dragged onto a folder, or onto a file of that folder, are moved there.
// Every rename and move can be undone and redone with the two arrows of the header. An open document follows its
// file, and is saved first if it had changes; File → Open recent follows too. The open folders themselves are not
// renamed or moved from the tree.

import AppKit

@MainActor
final class FileOps: ObservableObject {
    static let shared = FileOps()
    struct Op { let from: URL; let to: URL }

    @Published private(set) var undoStack: [Op] = []
    @Published private(set) var redoStack: [Op] = []
    @Published private(set) var generation = 0          // the trees reload when it changes

    /// What a drag of the tree carries: this prefix and the path (nothing else is taken as a drop).
    nonisolated static let dragPrefix = "gryphmark-tree:"

    static func isUnder(_ p: URL, _ dir: URL) -> Bool {
        let d = dir.standardizedFileURL.path
        return p.standardizedFileURL.path.lowercased().hasPrefix((d.hasSuffix("/") ? d : d + "/").lowercased())
    }

    /// A name macOS takes as one item: not empty, not . or .., without / or : (the Finder shows : as /).
    static func validName(_ n: String) -> Bool {
        !n.trimmingCharacters(in: .whitespaces).isEmpty && n != "." && n != ".." && !n.contains("/") && !n.contains(":") && !n.contains("\0")
    }

    /// One of the open folders of the panel: never renamed or moved from the tree.
    static func isRoot(_ u: URL) -> Bool {
        Prefs.shared.folders.contains { TreeState.canonical($0) == TreeState.canonical(u.path) }
    }

    /// A drop of `src` into `dir` is possible: not where it already is, not into itself.
    static func canDrop(_ src: URL, into dir: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue, !isRoot(src) else { return false }
        let parent = src.deletingLastPathComponent().standardizedFileURL.path.lowercased()
        return parent != dir.standardizedFileURL.path.lowercased()
            && src.standardizedFileURL.path.lowercased() != dir.standardizedFileURL.path.lowercased() && !isUnder(dir, src)
    }

    static func describe(_ op: Op) -> String {
        op.from.deletingLastPathComponent().path == op.to.deletingLastPathComponent().path
            ? "\(op.from.lastPathComponent) → \(op.to.lastPathComponent)"
            : "\(op.from.lastPathComponent) → \(op.to.deletingLastPathComponent().lastPathComponent)"
    }

    /// Moves or renames on disk. False, with a message in the status line of `doc`, when it could not be done.
    @discardableResult
    func move(_ from: URL, to: URL, record: Bool = true, doc: DocWindow?) async -> Bool {
        let fm = FileManager.default
        let from = from.standardizedFileURL, to = to.standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: from.path, isDirectory: &isDir) else { doc?.flash(L("ItemGone")); generation += 1; return false }
        if from.path == to.path { return false }
        let caseOnly = from.path.lowercased() == to.path.lowercased()
        if !caseOnly && fm.fileExists(atPath: to.path) { doc?.flash(L("NameExists", to.lastPathComponent)); return false }
        if isDir.boolValue && FileOps.isUnder(to, from) { doc?.flash(L("MoveIntoItself")); return false }

        // the open documents in it: saved first, then they follow their file
        let affected = DocWindow.all.filter { d in
            guard let p = d.model.path else { return false }
            return p.path.lowercased() == from.path.lowercased() || (isDir.boolValue && FileOps.isUnder(p, from))
        }
        for d in affected where d.model.dirty { guard await d.save(as: false) else { return false } }
        for d in affected { d.watch(nil) }
        do {
            if caseOnly {
                let hop = from.deletingLastPathComponent().appendingPathComponent(from.lastPathComponent + ".gm-rename-" + UUID().uuidString.prefix(6))
                try fm.moveItem(at: from, to: hop)
                try fm.moveItem(at: hop, to: to)
            } else {
                try fm.moveItem(at: from, to: to)
            }
        } catch {
            for d in affected { if let p = d.model.path { d.watch(p) } }
            doc?.flash(L("MoveFailed", error.localizedDescription))
            return false
        }
        for d in affected {
            guard let p = d.model.path else { continue }
            await d.relocate(to: URL(fileURLWithPath: to.path + String(p.path.dropFirst(from.path.count))))
        }
        Prefs.shared.follow(from: from.path, to: to.path, isDir: isDir.boolValue)
        if record { undoStack.append(Op(from: from, to: to)); redoStack.removeAll() }
        Wiki.forget()
        generation += 1
        return true
    }

    func undo(doc: DocWindow?) async {
        guard let op = undoStack.last else { return }
        if await move(op.to, to: op.from, record: false, doc: doc) { undoStack.removeLast(); redoStack.append(op) }
    }

    func redo(doc: DocWindow?) async {
        guard let op = redoStack.last else { return }
        if await move(op.from, to: op.to, record: false, doc: doc) { redoStack.removeLast(); undoStack.append(op) }
    }

    /// Right-click → Rename…: asks the new name, with the part before the extension selected.
    func rename(_ url: URL, doc: DocWindow?) {
        guard !FileOps.isRoot(url) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { doc?.flash(L("ItemGone")); generation += 1; return }
        let a = NSAlert()
        a.messageText = L("RenameTitle")
        a.informativeText = L("RenameName")
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        a.accessoryView = field
        a.addButton(withTitle: L("RenameButton"))
        a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = field
        let stem = (url.lastPathComponent as NSString).deletingPathExtension
        DispatchQueue.main.async { field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length) }
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        if name == url.lastPathComponent || name.isEmpty { return }
        guard FileOps.validName(name) else { doc?.flash(L("NameInvalid", name)); return }
        Task { await move(url, to: url.deletingLastPathComponent().appendingPathComponent(name), doc: doc) }
    }

    /// A drop on a row of the tree: the provider's text names what was dragged.
    func drop(_ providers: [NSItemProvider], into dir: URL, doc: DocWindow?) -> Bool {
        guard !Prefs.shared.treeLocked, let p = providers.first, p.canLoadObject(ofClass: NSString.self) else { return false }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, s.hasPrefix(FileOps.dragPrefix) else { return }
            let src = URL(fileURLWithPath: String(s.dropFirst(FileOps.dragPrefix.count)))
            DispatchQueue.main.async {
                guard FileOps.canDrop(src, into: dir) else { return }
                Task { await FileOps.shared.move(src, to: dir.appendingPathComponent(src.lastPathComponent), doc: doc) }
            }
        }
        return true
    }
}
