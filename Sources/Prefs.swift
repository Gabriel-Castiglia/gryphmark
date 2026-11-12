// Gryphmark: settings, text lookup and the theme colours.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// The settings live in the app's preferences (io.github.gabriel-castiglia.gryphmark). The
// screenshot and self-test modes switch persistence off, so they never touch them.

import AppKit
import SwiftUI

final class Prefs: ObservableObject {
    static let shared = Prefs()

    @Published var lang = "en" { didSet { save() } }
    @Published var theme = "auto" { didSet { save(); applyAppearance() } }      // auto, light, dark
    @Published var accent = "gold" { didSet { save(); applyDockIcon() } }
    @Published var mode = "visual" { didSet { save() } }                        // visual, source, preview
    @Published var spell = true { didSet { save() } }
    @Published var readOnly = false { didSet { save() } }
    @Published var zoom = 1.0 { didSet { save() } }
    @Published var sidebar = true { didSet { save() } }
    // Width of the sidebar and the share of its height that Contents takes (the rest is Files); set when a divider is let go.
    @Published var sidebarWidth = 260.0 { didSet { save() } }
    @Published var outlineShare = 0.45 { didSet { save() } }
    @Published var recent: [String] = [] { didSet { save() } }
    @Published var folders: [String] = [] { didSet { save() } }
    @Published var sampleShown = false { didSet { save() } }
    @Published private(set) var dark = false

    var persist = true
    private var loading = false
    private let d = UserDefaults.standard

    func load() {
        guard persist else { return }
        loading = true
        defer { loading = false }
        lang = d.string(forKey: "Lang") ?? Prefs.macLanguage
        theme = d.string(forKey: "Theme") ?? "auto"
        accent = d.string(forKey: "Accent") ?? "gold"
        mode = d.string(forKey: "Mode") ?? "visual"
        spell = d.object(forKey: "Spell") as? Bool ?? true
        readOnly = d.bool(forKey: "ReadOnly")
        zoom = max(0.5, min(3, d.object(forKey: "Zoom") as? Double ?? 1))
        sidebar = d.object(forKey: "Sidebar") as? Bool ?? true
        sidebarWidth = Prefs.clampWidth(d.object(forKey: "SidebarWidth") as? Double ?? 260)
        outlineShare = Prefs.clampShare(d.object(forKey: "OutlineShare") as? Double ?? 0.45)
        recent = d.stringArray(forKey: "Recent") ?? []
        folders = d.stringArray(forKey: "Folders") ?? []
        sampleShown = d.bool(forKey: "SampleShown")
    }

    func save() {
        guard persist, !loading else { return }
        let values: [String: Any] = [
            "Lang": lang, "Theme": theme, "Accent": accent, "Mode": mode, "Spell": spell, "ReadOnly": readOnly,
            "Zoom": zoom, "Sidebar": sidebar, "SidebarWidth": sidebarWidth, "OutlineShare": outlineShare, "Recent": recent, "Folders": folders, "SampleShown": sampleShown,
        ]
        for (k, v) in values { d.set(v, forKey: k) }
    }

    static let sidebarRange = 180.0...700.0
    static func clampWidth(_ w: Double) -> Double { min(max(w, sidebarRange.lowerBound), sidebarRange.upperBound) }
    static func clampShare(_ s: Double) -> Double { min(max(s, 0.1), 0.9) }

    /// The first time, Spanish if the Mac speaks it, English otherwise.
    static var macLanguage: String {
        Locale.preferredLanguages.first?.hasPrefix("es") == true ? "es" : "en"
    }

    func addRecent(_ path: String) {
        var r = recent.filter { $0 != path }
        r.insert(path, at: 0)
        recent = Array(r.prefix(12))
    }

    // MARK: appearance

    func applyAppearance() {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
        refreshDark()
    }

    func refreshDark() {
        let isDark = theme == "dark" || (theme == "auto" &&
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        if isDark != dark { dark = isDark }
    }

    func applyDockIcon() {
        if let img = Accent.get(accent).icon { NSApp.applicationIconImage = img }
    }

    var highlight: Color { Accent.get(accent).color(dark: dark) }
}

/// The text for `key` in the app's language; {0}, {1}… are replaced by `args`.
func L(_ key: String, _ args: CustomStringConvertible...) -> String {
    let row = STRINGS[key] ?? [key, key]
    var s = Prefs.shared.lang == "es" ? row[1] : row[0]
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: a.description) }
    return s
}

/// The twelve theme colours of the Windows version: the icon background (icono/accents/<key>.png,
/// made by tools/make_icons.py) and the highlight for the light and the dark chrome.
struct Accent {
    let key, en, es: String
    let light, dark: UInt32

    var name: String { Prefs.shared.lang == "es" ? es : en }

    func color(dark isDark: Bool) -> Color {
        let v = isDark ? dark : light
        return Color(.sRGB, red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    var icon: NSImage? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "accents") else { return nil }
        return NSImage(contentsOf: url)
    }

    static let all: [Accent] = [
        Accent(key: "gold", en: "Gold", es: "Dorado", light: 0x9A6F00, dark: 0xE2B84C),
        Accent(key: "purple", en: "Purple", es: "Morado", light: 0x5B2A86, dark: 0xB392E0),
        Accent(key: "sky", en: "Sky blue", es: "Celeste", light: 0x1A8CD8, dark: 0x5CB8F0),
        Accent(key: "ember", en: "Orange", es: "Naranja", light: 0xD9652F, dark: 0xF08A5D),
        Accent(key: "red", en: "Red", es: "Rojo", light: 0xC8102E, dark: 0xF2545B),
        Accent(key: "yellow", en: "Yellow", es: "Amarillo", light: 0xB88A00, dark: 0xF5C842),
        Accent(key: "green", en: "Green", es: "Verde", light: 0x1E8A43, dark: 0x4CC27A),
        Accent(key: "teal", en: "Teal", es: "Verde azulado", light: 0x00796B, dark: 0x4DB6AC),
        Accent(key: "blue", en: "Blue", es: "Azul", light: 0x1F5FD1, dark: 0x6E9BFF),
        Accent(key: "pink", en: "Pink", es: "Rosa", light: 0xC2185B, dark: 0xF06292),
        Accent(key: "black", en: "Black", es: "Negro", light: 0x1D1D1F, dark: 0xC7C7CC),
        Accent(key: "white", en: "White", es: "Blanco", light: 0x8E8E93, dark: 0xF5F5F7),
    ]

    static func get(_ key: String) -> Accent { all.first { $0.key == key } ?? all[0] }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
let appRepo = "Gabriel-Castiglia/gryphmark"
