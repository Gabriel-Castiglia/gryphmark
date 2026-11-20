// Vigia: what comes over from Gryphmark, the name of this app up to 2.2.1.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 20, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// The new name brought a new bundle identifier, so the Mac sees a new app: its settings would start empty. The first
// time Vigía (or one of its dedicated instances) starts, the settings kept under the old identifier come over whole;
// the main app also brings the crash-recovery drafts and makes the dedicated instances again as Vigía instances.
// Nothing old is deleted but the old instance apps, which go to the Trash once their Vigía copy exists.

import AppKit

enum Migration {
    static let oldMain = "io.github.gabriel-castiglia.gryph" + "mark"
    static let oldFolder = "Gryph" + "mark"

    /// The identifier this app or instance had: the same with the old name.
    static func oldID(_ id: String) -> String {
        id.hasPrefix(Instance.mainID) ? oldMain + id.dropFirst(Instance.mainID.count) : id
    }

    /// The settings, the first time: the old domain is copied whole when the new one is still empty.
    static func settings() {
        guard let id = Bundle.main.bundleIdentifier, id.hasPrefix(Instance.mainID) else { return }
        let d = UserDefaults.standard
        if let mine = d.persistentDomain(forName: id), !mine.isEmpty { return }
        guard let old = d.persistentDomain(forName: oldID(id)), !old.isEmpty else { return }
        d.setPersistentDomain(old, forName: id)
    }

    /// Recovery drafts: Application Support/Gryphmark becomes Application Support/Vigia (each instance's folder
    /// under its new identifier). Only when Vigia has none yet.
    static func drafts() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent(oldFolder, isDirectory: true), new = base.appendingPathComponent("Vigia", isDirectory: true)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        copy(old, to: new)
    }

    private static func copy(_ from: URL, to: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: to, withIntermediateDirectories: true)
        for item in (try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
            let name = item.lastPathComponent.replacingOccurrences(of: oldMain, with: Instance.mainID)
            let dest = to.appendingPathComponent(name)
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { copy(item, to: dest) }
            else { try? fm.copyItem(at: item, to: dest) }
        }
    }

    /// The old spec of an instance made by Gryphmark (its Info.plist), or nil.
    static func oldSpec(_ app: URL) -> Instance.Spec? {
        guard let p = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let name = p["GMProfile"] as? String,
              (p["CFBundleIdentifier"] as? String)?.hasPrefix(oldMain + ".profile.") == true else { return nil }
        return Instance.Spec(name: name, accent: p["GMAccent"] as? String ?? "gold", folders: p["GMFolders"] as? [String] ?? [],
                             home: p["GMHome"] as? String, startReadOnly: p["GMStartReadOnly"] as? Bool ?? false,
                             startMode: p["GMStartMode"] as? String)
    }

    /// Each dedicated instance made by Gryphmark is made again as a Vigía instance with the same folders, home file,
    /// colour and start options; then the old one goes to the Trash. One that is running is left for the next start.
    static func instances(from source: URL) {
        let fm = FileManager.default
        for app in (try? fm.contentsOfDirectory(at: Instance.appsFolder, includingPropertiesForKeys: nil)) ?? [] {
            guard app.pathExtension == "app", let spec = oldSpec(app),
                  let oldBundle = Bundle(url: app)?.bundleIdentifier,
                  NSRunningApplication.runningApplications(withBundleIdentifier: oldBundle).isEmpty else { continue }
            if fm.fileExists(atPath: Instance.bundleURL(spec.name).path) || (try? Instance.make(spec, from: source)) != nil {
                NSWorkspace.shared.recycle([app]) { _, _ in }
            }
        }
    }
}
