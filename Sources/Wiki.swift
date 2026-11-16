// Gryphmark: [[name]] links, and the folders a document's links and pictures may reach.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 11, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// A [[name]] (also [[name|text]] and [[name#heading]]) in the GitHub view is a link to the Markdown
// file called name.md in the folders open in the Files panel or next to the document, as in a wiki.
// When two files share the name, the one nearest the document wins. Names that match no file are
// shown as missing, so a broken link can be seen without clicking it.
//
// Reach: a document opened from inside a folder of the Files panel may link to, and show pictures
// from, every folder of the panel (../other/file.md works); any other document only reaches its
// own folder, as before. Nothing outside those folders is ever served or opened.

import Foundation

enum Wiki {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// The folders the document in `docFolder` may reach, given the folders of the Files panel.
    static func reach(docFolder: URL?, panel: [String]) -> [URL] {
        guard let dir = docFolder?.standardizedFileURL else { return [] }
        let roots = panel.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        return roots.contains(where: { inside(dir, $0) }) ? [dir] + roots : [dir]
    }

    /// True when `file` is `root` or lies under it, after following symbolic links.
    static func inside(_ file: URL, _ root: URL) -> Bool {
        let f = file.standardizedFileURL.resolvingSymlinksInPath().path
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        return f == r || f.hasPrefix(r.hasSuffix("/") ? r : r + "/")
    }

    static func inside(_ file: URL, any roots: [URL]) -> Bool { roots.contains { inside(file, $0) } }

    /// The key a name is looked up by: no extension, no heading, no case, composed accents.
    static func key(_ name: String) -> String {
        var n = name.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespaces)
        if let i = n.firstIndex(where: { $0 == "#" || $0 == "|" }) { n = String(n[..<i]) }
        n = n.trimmingCharacters(in: .whitespaces)
        if let dot = n.lastIndex(of: "."), extensions.contains(String(n[n.index(after: dot)...]).lowercased()) { n = String(n[..<dot]) }
        return n.lowercased()
    }

    // Markdown files of the searched folders by key, kept for two seconds: a page with a hundred
    // links asks once, and a file an assistant has just written is found on the next click.
    private static var cache: (roots: [URL], at: Date, files: [String: [URL]])?
    private static let lock = NSLock()

    private static func files(in roots: [URL]) -> [String: [URL]] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache, c.roots == roots, Date().timeIntervalSince(c.at) < 2 { return c.files }
        var out: [String: [URL]] = [:]
        let fm = FileManager.default
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                if e.level > 12 { e.skipDescendants(); continue }
                guard extensions.contains(u.pathExtension.lowercased()) else { continue }
                let k = key(u.deletingPathExtension().lastPathComponent)
                let s = u.standardizedFileURL
                if !(out[k]?.contains(s) ?? false) { out[k, default: []].append(s) }
            }
        }
        cache = (roots, Date(), out)
        return out
    }

    /// The file a [[name]] points to, or nil.
    static func resolve(_ name: String, from docFolder: URL?, panel: [String]) -> URL? {
        let roots = searched(docFolder: docFolder, panel: panel)
        guard let hits = files(in: roots)[key(name)], !hits.isEmpty else { return nil }
        guard let dir = docFolder?.standardizedFileURL.pathComponents, hits.count > 1 else { return hits.first }
        // the nearest: the longest common start of the path, then the shortest path
        func shared(_ u: URL) -> Int { zip(u.deletingLastPathComponent().pathComponents, dir).prefix { $0 == $1 }.count }
        return hits.max { (shared($0), -$0.pathComponents.count) < (shared($1), -$1.pathComponents.count) }
    }

    /// For each name, whether it points to a file.
    static func exist(_ names: [String], from docFolder: URL?, panel: [String]) -> [String: Bool] {
        let all = files(in: searched(docFolder: docFolder, panel: panel))
        var out: [String: Bool] = [:]
        for n in names { out[n] = !(all[key(n)] ?? []).isEmpty }
        return out
    }

    /// The file a ![[name]] picture points to: that file name (or the end of that path) in the folders searched for
    /// [[name]], the nearest to the document first; nil when there is none.
    static func findFile(_ name: String, from docFolder: URL?, panel: [String]) -> URL? {
        let want = name.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = (want as NSString).lastPathComponent.lowercased()
        guard !file.isEmpty else { return nil }
        let tail = "/" + want.lowercased()
        var hits: [URL] = []
        let fm = FileManager.default
        for root in searched(docFolder: docFolder, panel: panel) {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let u as URL in e {
                if e.level > 12 { e.skipDescendants(); continue }
                if u.lastPathComponent.lowercased() == file, u.standardizedFileURL.path.lowercased().hasSuffix(tail) { hits.append(u.standardizedFileURL) }
                if hits.count > 50 { break }
            }
        }
        guard let dir = docFolder?.standardizedFileURL.pathComponents, hits.count > 1 else { return hits.first }
        func shared(_ u: URL) -> Int { zip(u.deletingLastPathComponent().pathComponents, dir).prefix { $0 == $1 }.count }
        return hits.max { (shared($0), -$0.pathComponents.count) < (shared($1), -$1.pathComponents.count) }
    }

    /// The panel folders plus the document's own folder (each folder searched once).
    private static func searched(docFolder: URL?, panel: [String]) -> [URL] {
        var roots = panel.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        if let d = docFolder?.standardizedFileURL, !roots.contains(where: { inside(d, $0) }) { roots.append(d) }
        return roots
    }

    static func forget() { lock.lock(); cache = nil; lock.unlock() }
}
