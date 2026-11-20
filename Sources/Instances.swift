// Vigia: dedicated instances, each one its own app with its own icon, settings and session.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 11, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// On Windows a dedicated instance is Vigia started with --profile "Name". On the Mac a Dock
// icon belongs to an app, so a dedicated instance is an app of its own: a copy of Vigia in
// ~/Applications ("Name (Vigía).app", an APFS clone that takes no space) with another bundle
// identifier, so the Mac keeps its settings, window and recent files apart from the main app's,
// and an icon in its theme colour. Its Info.plist says which folders it shows in the Files panel,
// which file it opens at start, and whether it always starts read-only and in which view.
// It never registers as a Markdown app, so the Finder keeps opening .md files with the main one.
// The main app rebuilds every instance that is older than itself, or whose colour was changed
// from inside it, each time it starts (never while that instance is running).

import AppKit
import CoreServices
import ImageIO
import UniformTypeIdentifiers

enum Instance {
    static let mainID = "io.github.gabriel-castiglia.vigia"
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// Name of this dedicated instance; nil in the main app.
    static var profile: String? { info["GMProfile"] as? String }
    static var isDedicated: Bool { profile != nil }
    static var folders: [String] { info["GMFolders"] as? [String] ?? [] }
    static var home: String? { info["GMHome"] as? String }
    static var startReadOnly: Bool { info["GMStartReadOnly"] as? Bool ?? false }
    static var startMode: String? { info["GMStartMode"] as? String }
    static var accent: String? { info["GMAccent"] as? String }

    /// Where the instances live. The self-test points it to a temporary folder.
    static var appsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)

    /// What an instance is made of: all of it lives in its Info.plist.
    struct Spec: Equatable {
        var name: String
        var accent: String
        var folders: [String] = []
        var home: String? = nil
        var startReadOnly = false
        var startMode: String? = nil
    }

    /// The name with the characters a file name cannot carry replaced.
    static func safeName(_ name: String) -> String {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines).map { "/:\\".contains($0) ? "_" : String($0) }.joined()
        return s.isEmpty ? "Vigía" : s
    }

    /// Bundle identifier of an instance: letters and digits of its name only.
    static func bundleID(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var slug = String(folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return mainID + ".profile." + (slug.isEmpty ? "instance" : slug)
    }

    static func bundleURL(_ name: String) -> URL { appsFolder.appendingPathComponent(safeName(name) + " (Vigía).app", isDirectory: true) }

    /// Profile name for a file or a folder: its name without extension (as on Windows).
    static func name(for path: URL) -> String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir)
        return isDir.boolValue ? path.lastPathComponent : path.deletingPathExtension().lastPathComponent
    }

    /// The main Vigia: this app, or (inside an instance) the one the Mac knows by its identifier.
    static var mainBundle: URL? {
        isDedicated ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainID) : Bundle.main.bundleURL
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    // MARK: making one

    /// Builds the instance app from `source` (the main Vigia), or rebuilds it in place. The settings
    /// of a new instance start from the main app's (language, theme, view, spelling, zoom); a rebuilt one
    /// keeps its own.
    @discardableResult
    static func make(_ spec: Spec, from source: URL) throws -> URL {
        let fm = FileManager.default
        let dest = bundleURL(spec.name)
        let id = bundleID(spec.name)
        if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            throw Failure(L("InstanceRunning", spec.name))
        }
        try fm.createDirectory(at: appsFolder, withIntermediateDirectories: true)
        let tmp = appsFolder.appendingPathComponent(".vigia-\(UUID().uuidString).app", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        try fm.copyItem(at: source, to: tmp)   // APFS: a clone, no space taken

        let plistURL = tmp.appendingPathComponent("Contents/Info.plist")
        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else { throw Failure("Info.plist") }
        plist["CFBundleIdentifier"] = id
        plist["CFBundleName"] = safeName(spec.name)
        plist["CFBundleDisplayName"] = safeName(spec.name) + " (Vigía)"
        plist.removeValue(forKey: "CFBundleDocumentTypes")
        plist["GMProfile"] = spec.name
        plist["GMAccent"] = spec.accent
        plist["GMFolders"] = spec.folders
        plist["GMStartReadOnly"] = spec.startReadOnly
        if let h = spec.home { plist["GMHome"] = h } else { plist.removeValue(forKey: "GMHome") }
        if let m = spec.startMode { plist["GMStartMode"] = m } else { plist.removeValue(forKey: "GMStartMode") }
        guard (plist as NSDictionary).write(to: plistURL, atomically: true) else { throw Failure("Info.plist") }

        let accentPNG = tmp.appendingPathComponent("Contents/Resources/accents/\(spec.accent).png")
        try writeIcns(from: accentPNG, to: tmp.appendingPathComponent("Contents/Resources/Vigia.icns"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", tmp.path])

        seed(id: id, spec: spec)
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: dest)
        }
        LSRegisterURL(dest as CFURL, true)
        NSWorkspace.shared.noteFileSystemChanged(dest.path)
        return dest
    }

    /// A new instance starts with the main preferences and an empty session; one that already has
    /// settings only gets the folders of its spec when it has none.
    private static func seed(id: String, spec: Spec) {
        guard let d = UserDefaults(suiteName: id) else { return }
        if d.bool(forKey: "InstanceSeeded") {
            if (d.stringArray(forKey: "Folders") ?? []).isEmpty, !spec.folders.isEmpty { d.set(spec.folders, forKey: "Folders") }
            return
        }
        // inside the main app its own settings are the standard ones (a suite of its own id would not work)
        if let main = Bundle.main.bundleIdentifier == mainID ? UserDefaults.standard : UserDefaults(suiteName: mainID) {
            for k in ["Lang", "Theme", "Mode", "Spell", "Zoom"] { if let v = main.object(forKey: k) { d.set(v, forKey: k) } }
        }
        d.set(spec.accent, forKey: "Accent")
        d.set(spec.folders, forKey: "Folders")
        d.set(true, forKey: "Sidebar")
        d.set(true, forKey: "SampleShown")
        d.set(spec.startReadOnly, forKey: "ReadOnly")
        if let m = spec.startMode { d.set(m, forKey: "Mode") }
        d.set(true, forKey: "InstanceSeeded")
        d.synchronize()
    }

    /// An icns with the sizes the Dock and the Finder use, from one picture of the icon.
    static func writeIcns(from png: URL, to icns: URL) throws {
        guard let src = CGImageSourceCreateWithURL(png as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw Failure(png.lastPathComponent) }
        let sizes = [16, 32, 64, 128, 256, 512]
        guard let out = CGImageDestinationCreateWithURL(icns as CFURL, UTType.icns.identifier as CFString, sizes.count, nil) else {
            throw Failure("icns")
        }
        for s in sizes {
            guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure("icns") }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: s, height: s))
            if let scaled = ctx.makeImage() { CGImageDestinationAddImage(out, scaled, nil) }
        }
        guard CGImageDestinationFinalize(out) else { throw Failure("icns") }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure("\((tool as NSString).lastPathComponent): \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // MARK: finding and refreshing them

    /// The spec of an instance app, read back from its Info.plist (nil for anything else).
    static func spec(of app: URL) -> Spec? {
        guard let p = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let name = p["GMProfile"] as? String,
              (p["CFBundleIdentifier"] as? String)?.hasPrefix(mainID + ".profile.") == true else { return nil }
        return Spec(name: name, accent: p["GMAccent"] as? String ?? "gold", folders: p["GMFolders"] as? [String] ?? [],
                    home: p["GMHome"] as? String, startReadOnly: p["GMStartReadOnly"] as? Bool ?? false,
                    startMode: p["GMStartMode"] as? String)
    }

    static func all() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: appsFolder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "app" && spec(of: $0) != nil }
    }

    /// Run by the main app at start: an instance older than the app, or whose colour was changed from
    /// inside it (the Dock shows the bundle's icon while it is closed), is rebuilt.
    static func refreshAll() {
        guard !isDedicated else { return }
        let source = Bundle.main.bundleURL
        let version = "\(appVersion) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))"
        DispatchQueue.global(qos: .utility).async {
            for app in all() {
                guard var s = spec(of: app), let p = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { continue }
                let theirs = "\(p["CFBundleShortVersionString"] as? String ?? "") (\(p["CFBundleVersion"] as? String ?? ""))"
                let colour = UserDefaults(suiteName: bundleID(s.name))?.string(forKey: "Accent") ?? s.accent
                guard theirs != version || colour != s.accent else { continue }
                s.accent = Accent.all.contains { $0.key == colour } ? colour : s.accent
                _ = try? make(s, from: source)
            }
        }
    }

    /// Opens the instance app (with these files, if any).
    static func launch(_ app: URL, files: [URL] = []) {
        let c = NSWorkspace.OpenConfiguration()
        c.activates = true
        if files.isEmpty { NSWorkspace.shared.openApplication(at: app, configuration: c) }
        else { NSWorkspace.shared.open(files, withApplicationAt: app, configuration: c) }
    }

    // MARK: the command line

    /// vigia --make-instance "Name" [--accent red] [--folder PATH]… [--home FILE] [--read-only] [--mode preview] [--open]
    /// Prints the path of the app and exits (0 when it was made).
    static func makeFromCommandLine(_ a: [String]) -> Never {
        func value(_ flag: String) -> String? { a.firstIndex(of: flag).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
        func path(_ s: String) -> String { URL(fileURLWithPath: (s as NSString).expandingTildeInPath).standardizedFileURL.path }
        guard let name = value("--make-instance"), !name.hasPrefix("--") else {
            FileHandle.standardError.write(Data("--make-instance needs a name\n".utf8)); exit(2)
        }
        var folders: [String] = []
        for (i, x) in a.enumerated() where x == "--folder" && i + 1 < a.count { folders.append(path(a[i + 1])) }
        let accent = value("--accent") ?? "gold"
        guard Accent.all.contains(where: { $0.key == accent }) else {
            FileHandle.standardError.write(Data("unknown colour: \(accent) (\(Accent.all.map(\.key).joined(separator: ", ")))\n".utf8)); exit(2)
        }
        let spec = Spec(name: name, accent: accent, folders: folders, home: value("--home").map(path),
                        startReadOnly: a.contains("--read-only"), startMode: value("--mode"))
        guard let source = mainBundle else { FileHandle.standardError.write(Data("Vigía not found\n".utf8)); exit(1) }
        do {
            let app = try make(spec, from: source)
            print(app.path)
            if a.contains("--open") { try run("/usr/bin/open", [app.path]) }   // waits: the process ends right after
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
