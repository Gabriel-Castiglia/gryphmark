// Gryphmark: what a link in a document may open.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// A document must never be able to run a program. The rules are those of the Windows version:
//   - a Markdown file the document may reach opens in Gryphmark (its folder, or every folder of
//     the Files panel when the document is inside one of them: Wiki.reach);
//   - a picture or a PDF it may reach opens in its viewer;
//   - any other file it may reach is only shown in the Finder;
//   - outside those folders, only web pages (http, https) and e-mail (mailto) open;
//   - everything else (file:, javascript:, app schemes, ...) is ignored.

import Foundation

enum LinkAction: Equatable {
    case openDocument(URL)
    case openViewer(URL)
    case reveal(URL)
    case external(URL)
    case ignore
}

enum LinkPolicy {
    static let markdown: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]
    static let viewable: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "pdf"]

    static func decide(_ href: String, reach: [URL]) -> LinkAction {
        guard let url = URL(string: href), let scheme = url.scheme?.lowercased() else { return .ignore }
        if scheme == Schemes.doc {
            guard let file = Schemes.file(of: url), Wiki.inside(file, any: reach) else { return .ignore }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) else { return .ignore }
            if isDir.boolValue { return .reveal(file) }
            let ext = file.pathExtension.lowercased()
            if markdown.contains(ext) { return .openDocument(file) }
            if viewable.contains(ext) { return .openViewer(file) }
            return .reveal(file)
        }
        if scheme == "http" || scheme == "https" || scheme == "mailto" { return .external(url) }
        return .ignore
    }
}
