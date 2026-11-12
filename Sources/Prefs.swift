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
    // The Files panel, as on Windows: pinned folders go first; the rest in the chosen order; each folder a colour.
    @Published var pinned: [String] = [] { didSet { save() } }
    @Published var startupFolders = "restore" { didSet { save() } }     // restore, clean, pinned
    @Published var folderSort = "opened" { didSet { save() } }          // opened, az, za, modified
    @Published var folderColors = "theme" { didSet { save() } }         // theme, multi, none
    @Published var folderColorMap: [String: Double] = [:] { didSet { save() } }   // hue chosen by hand
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
        pinned = d.stringArray(forKey: "PinnedFolders") ?? []
        startupFolders = ["restore", "clean", "pinned"].contains(d.string(forKey: "StartupFolders") ?? "") ? d.string(forKey: "StartupFolders")! : "restore"
        folderSort = ["opened", "az", "za", "modified"].contains(d.string(forKey: "FolderSort") ?? "") ? d.string(forKey: "FolderSort")! : "opened"
        folderColors = ["theme", "multi", "none"].contains(d.string(forKey: "FolderColors") ?? "") ? d.string(forKey: "FolderColors")! : "theme"
        folderColorMap = (d.dictionary(forKey: "FolderColorMap") as? [String: Double]) ?? [:]
        sampleShown = d.bool(forKey: "SampleShown")
    }

    func save() {
        guard persist, !loading else { return }
        let values: [String: Any] = [
            "Lang": lang, "Theme": theme, "Accent": accent, "Mode": mode, "Spell": spell, "ReadOnly": readOnly,
            "Zoom": zoom, "Sidebar": sidebar, "SidebarWidth": sidebarWidth, "OutlineShare": outlineShare, "Recent": recent, "Folders": folders, "SampleShown": sampleShown,
            "PinnedFolders": pinned, "StartupFolders": startupFolders, "FolderSort": folderSort, "FolderColors": folderColors,
            "FolderColorMap": folderColorMap,
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

    /// What the panel opens with at start: the folders of the last session (pinned ones included), none, or
    /// only the pinned ones. Pinned folders stay pinned when they are not opened.
    func applyStartupFolders() {
        pinned.removeAll { $0.isEmpty }
        switch startupFolders {
        case "clean": folders = []
        case "pinned": folders = pinned
        default: for p in pinned where !folders.contains(p) { folders.append(p) }
        }
    }

    func isPinned(_ dir: String) -> Bool { pinned.contains(dir) }

    func togglePin(_ dir: String) {
        if isPinned(dir) { pinned.removeAll { $0 == dir } } else { pinned.append(dir) }
    }

    /// Closing a folder also unpins it and forgets its colour (as on Windows).
    func closeFolder(_ dir: String) {
        folders.removeAll { $0 == dir }
        pinned.removeAll { $0 == dir }
        folderColorMap[dir] = nil
    }

    /// Swaps a folder with its neighbour in the opening order; the order goes back to "order opened".
    func moveFolder(_ dir: String, by delta: Int) {
        guard let i = folders.firstIndex(of: dir), folders.indices.contains(i + delta) else { return }
        folders.swapAt(i, i + delta)
        folderSort = "opened"
    }

    /// Pinned folders first, in the order they were pinned, then the rest by the chosen order.
    var orderedFolders: [String] {
        let top = pinned.filter { folders.contains($0) }
        let rest = folders.filter { !top.contains($0) }
        let name = { (p: String) in (p as NSString).lastPathComponent }
        let sorted: [String]
        switch folderSort {
        case "az": sorted = rest.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        case "za": sorted = rest.sorted { name($0).localizedStandardCompare(name($1)) == .orderedDescending }
        case "modified":
            let date = { (p: String) in ((try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date) ?? .distantPast }
            sorted = rest.sorted { date($0) > date($1) }
        default: sorted = rest
        }
        return top + sorted
    }

    /// The colour of an open folder: chosen by hand, or tones of the theme colour, or spread around the colour
    /// wheel (multicolour), as on Windows. Its place in the opening order keeps it the same when the order changes.
    /// nil when folders have no colour.
    func folderTint(_ dir: String) -> (fill: Color, edge: Color)? {
        guard folderColors != "none" else { return nil }
        let i = max(0, folders.firstIndex(of: dir) ?? 0)
        let (ah, asat, _) = Prefs.hsl(Accent.get(accent).light)
        var grey = false
        let hue: Double
        if let manual = folderColorMap[dir] { hue = manual }
        else if folderColors == "multi" { hue = (ah + Double(i) * 137.508).truncatingRemainder(dividingBy: 360) }
        else {
            grey = asat < 0.15        // black and white themes: shades of grey
            let steps: [Double] = [0, 22, -22, 44, -44, 66, -66, 11, -11, 33, -33]
            hue = (ah + steps[i % steps.count] + 360).truncatingRemainder(dividingBy: 360)
        }
        let s = grey ? 0.0 : 1.0
        let fill = dark ? Prefs.color(hue, 0.30 * s, grey ? 0.17 + Double(i % 4) * 0.025 : 0.20)
                        : Prefs.color(hue, 0.65 * s, grey ? 0.95 - Double(i % 4) * 0.02 : 0.94)
        let edge = dark ? Prefs.color(hue, 0.55 * s, grey ? 0.55 : 0.62) : Prefs.color(hue, 0.55 * s, grey ? 0.55 : 0.58)
        return (fill, edge)
    }

    /// The twelve colours of the Colour menu: hue every 30 degrees.
    static let folderHues: [(hue: Double, en: String, es: String)] = [
        (0, "Red", "Rojo"), (30, "Orange", "Naranja"), (60, "Yellow", "Amarillo"), (90, "Lime", "Lima"),
        (120, "Green", "Verde"), (150, "Mint", "Menta"), (180, "Cyan", "Cian"), (210, "Sky", "Celeste"),
        (240, "Blue", "Azul"), (270, "Violet", "Violeta"), (300, "Purple", "Morado"), (330, "Pink", "Rosa"),
    ]

    static func hsl(_ rgb: UInt32) -> (h: Double, s: Double, l: Double) {
        let r = Double(rgb >> 16 & 0xFF) / 255, g = Double(rgb >> 8 & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 1e-9 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h = mx == r ? (g - b) / d + (g < b ? 6 : 0) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
        h *= 60
        return (h, s, l)
    }

    static func color(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let c = (1 - abs(2 * l - 1)) * s, hp = h / 60, x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hp {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return Color(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: 1)
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
