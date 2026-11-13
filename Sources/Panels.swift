// Gryphmark: small dialogs, and the Theme and About windows.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only

import AppKit
import SwiftUI

enum Dialogs {
    /// Asks for a few lines of text in a sheet. nil when cancelled. `browse` adds a button that
    /// fills the first two fields (used to pick a picture).
    @MainActor
    static func ask(_ title: String, fields: [(String, String)], browse: (() -> (String, String)?)? = nil,
                    in window: NSWindow?) async -> [String]? {
        let a = NSAlert()
        a.messageText = title
        a.addButton(withTitle: L("Insert"))
        a.addButton(withTitle: L("Cancel"))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        var boxes: [NSTextField] = []
        for (label, value) in fields {
            stack.addArrangedSubview(NSTextField(labelWithString: label))
            let t = NSTextField(string: value)
            t.frame.size.width = 320
            t.widthAnchor.constraint(equalToConstant: 320).isActive = true
            stack.addArrangedSubview(t)
            boxes.append(t)
        }
        if let browse {
            let b = BlockButton(title: L("Browse")) {
                if let (f, alt) = browse() { boxes[0].stringValue = f; if boxes.count > 1 { boxes[1].stringValue = alt } }
            }
            stack.addArrangedSubview(b)
        }
        stack.frame.size = stack.fittingSize
        a.accessoryView = stack
        a.window.initialFirstResponder = boxes.first
        let r: NSApplication.ModalResponse
        if let window { r = await a.beginSheetModal(for: window) } else { r = a.runModal() }
        return r == .alertFirstButtonReturn ? boxes.map(\.stringValue) : nil
    }
}

final class BlockButton: NSButton {
    private let run: () -> Void
    init(title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}

struct ThemeView: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("ThemeLook")).font(.system(size: 13, weight: .semibold))
            Picker("", selection: $prefs.theme) {
                Text(L("ThemeAuto")).tag("auto")
                Text(L("ThemeLight")).tag("light")
                Text(L("ThemeDark")).tag("dark")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Text(L("ThemeAutoTip")).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(L("ThemeColor")).font(.system(size: 13, weight: .semibold)).padding(.top, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 8), count: 6), spacing: 12) {
                ForEach(Accent.all, id: \.key) { a in
                    let on = prefs.accent == a.key
                    Button { prefs.accent = a.key } label: {
                        VStack(spacing: 4) {
                            if let img = a.icon { Image(nsImage: img).resizable().interpolation(.high).frame(width: 56, height: 56) }
                            Text(a.name).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(5).frame(width: 88)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? a.color(dark: prefs.dark).opacity(0.15) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? a.color(dark: prefs.dark) : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("ThemeNote")).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 608, alignment: .leading)
        .id(prefs.lang)
    }
}

struct AboutView: View {
    @ObservedObject var prefs: Prefs
    @StateObject private var copied = Flag()

    final class Flag: ObservableObject { @Published var on = false }

    /// What a problem report needs, as Copy info gives it on Windows.
    static var info: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let webkit = Bundle(identifier: "com.apple.WebKit")?.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Gryphmark \(appVersion) — © 2026 Gabriel Castiglia — GPL-2.0-only\n" +
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · arm64\nWebKit \(webkit)"
    }

    var body: some View {
        VStack(spacing: 10) {
            if let img = Accent.get(prefs.accent).icon { Image(nsImage: img).resizable().frame(width: 96, height: 96) }
            Text("Gryphmark").font(.system(size: 22, weight: .semibold))
            Text(L("AboutVersion", appVersion)).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L("AboutTagline"))
            Text(L("AboutBy")).fontWeight(.semibold)
            Link("github.com/" + appRepo, destination: URL(string: "https://github.com/" + appRepo)!)
            Text(L("AboutLicense")).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(L("AboutCreditsTitle")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
            Text(credits).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(L("AboutIcon")).font(.system(size: 11)).foregroundStyle(.secondary)
            Button(L(copied.on ? "AboutCopied" : "AboutCopy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AboutView.info, forType: .string)
                copied.on = true
            }.padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 500)
        .tint(prefs.highlight)
        .id(prefs.lang)
    }

    private var credits: String {
        "TOAST UI Editor · ProseMirror · marked · github-markdown-css ·\nMermaid · KaTeX · gemoji — MIT\n" +
            "highlight.js · jsdiff — BSD-3-Clause\nDOMPurify — MPL-2.0\nSwift, AppKit, SwiftUI, WebKit (Apple)"
    }
}
