// Gryphmark: --self-test, run in the real window with the real page.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// Checks, each with a case that must fail when the thing is broken:
//   - the page starts in WebKit and loads the sample (words and contents counted);
//   - a hostile document cannot run script: event handlers, <script> and javascript: links
//     are removed from the GitHub view, and a marker set by them stays unset;
//   - the link rules (programs are only shown in the Finder, never run);
//   - saving writes back the file's own BOM and CRLF line endings, byte for byte;
//   - live reload: a save by rename over the file, a delete and re-create, and a plain write
//     each show the new text, without marking the document modified; with unsaved changes the
//     window keeps its text and asks instead;
//   - export to HTML carries the text and no scripts.
// Temporary files go to a fresh folder that is removed at the end. Exit 0 when all pass.

import AppKit

enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures += 1 }
        FileHandle.standardError.write(Data("\(ok ? "ok  " : "FAIL") \(name)\(ok ? "" : ": " + detail())\n".utf8))
    }

    static func start() {
        let app = NSApp.delegate as! AppDelegate
        let d = app.newWindow()
        d.onReady = { Task { @MainActor in await run(d) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
            FileHandle.standardError.write(Data("self-test: timed out\n".utf8)); exit(2)
        }
    }

    @MainActor
    private static func wait(_ seconds: Double, until: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if await until() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await until()
    }

    @MainActor
    private static func markdown(_ d: DocWindow) async -> String {
        (await d.web.call("return mdApp.getMarkdown()") as? String) ?? ""
    }

    @MainActor
    static func run(_ d: DocWindow) async {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("gryphmark-selftest-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Texts: both languages present and filled.
        check("strings: every text in both languages", STRINGS.values.allSatisfy { $0.count == 2 && !$0[0].isEmpty && !$0[1].isEmpty })

        // The page and the sample.
        let app = NSApp.delegate as! AppDelegate
        app.openSample(in: d)
        let sampleOK = await wait(10) { d.model.isSample && d.model.words > 100 && !d.model.outline.isEmpty }
        check("sample: loaded with words and contents", sampleOK, "words \(d.model.words), headings \(d.model.outline.count)")

        // The window resizes freely: the content never holds it taller or wider than asked.
        if let w = d.window {
            w.setContentSize(NSSize(width: 800, height: 500))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let small = w.contentRect(forFrameRect: w.frame).size
            w.setContentSize(NSSize(width: 1000, height: 700))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let big = w.contentRect(forFrameRect: w.frame).size
            let fill = d.web.view.convert(d.web.view.bounds, to: nil)
            let content = w.contentView?.bounds ?? .zero
            check("window: the page reaches the status line, the toolbar the top", fill.minY < 40 && content.height - fill.maxY < 60,
                  "page \(fill) in \(content)")
            check("window: resizes in both directions", abs(small.height - 500) < 2 && abs(big.height - 700) < 2 &&
                  abs(small.width - 800) < 2, "\(small) \(big)")
        }

        // Dark theme: its stylesheets load from the app's own scheme.
        Prefs.shared.theme = "dark"
        _ = await wait(3) { Prefs.shared.dark }
        await d.applyTheme()
        let darkOK = await wait(5) {
            (await d.web.call("""
                const s = Array.from(document.styleSheets).find(x => (x.href || '').includes('github-markdown-dark'));
                try { return s ? s.cssRules.length : 0 } catch (e) { return -1 }
                """) as? Int ?? 0) > 10
        }
        check("theme: dark stylesheets load", darkOK)
        Prefs.shared.theme = "light"
        _ = await wait(3) { !Prefs.shared.dark }
        await d.applyTheme()

        // A Mermaid diagram draws (the library loads on demand from the app's scheme).
        await d.loadText("# D\n\n```mermaid\ngraph TD; A-->B\n```\n", sample: false)
        d.setMode("preview")
        let mermaidOK = await wait(8) {
            (await d.web.call("return document.querySelectorAll('#preview svg').length") as? Int ?? 0) > 0
        }
        check("mermaid: diagram drawn in the GitHub view", mermaidOK)
        d.setMode("visual")

        // A hostile document.
        let hostile = """
            # Hostile

            <img src="nothing.png" onerror="window.__pwned = 1">

            <script>window.__pwned = 2</script>

            <a href="javascript:window.__pwned = 3">click</a> <iframe src="https://example.com"></iframe>

            <svg><a href="javascript:window.__pwned=4"><text>x</text></a></svg>
            """
        let hostileFile = tmp.appendingPathComponent("hostile.md")
        try? Data(hostile.utf8).write(to: hostileFile)
        await d.load(hostileFile)
        d.setMode("preview")
        try? await Task.sleep(nanoseconds: 800_000_000)
        let html = (await d.web.call("return document.getElementById('preview').innerHTML") as? String) ?? ""
        let pwned = await d.web.call("return window.__pwned === undefined ? 0 : window.__pwned") as? Int ?? -1
        check("hostile: no script ran", pwned == 0, "marker \(pwned)")
        check("hostile: handlers, scripts, frames and javascript: links removed",
              !html.contains("onerror") && !html.lowercased().contains("<script") && !html.contains("javascript:") &&
                  !html.lowercased().contains("<iframe") && html.contains("Hostile"), String(html.prefix(300)))
        // Clicking every link in the view must not run anything either.
        await d.web.call("document.querySelectorAll('#preview a').forEach(a => a.click())")
        try? await Task.sleep(nanoseconds: 300_000_000)
        let afterClick = await d.web.call("return window.__pwned === undefined ? 0 : window.__pwned") as? Int ?? -1
        check("hostile: clicked links run nothing", afterClick == 0, "marker \(afterClick)")
        d.setMode("visual")

        // Link rules.
        for (name, content) in [("run.command", "#!/bin/sh\n"), ("note.md", "# n\n"), ("pic.png", "x"), ("app.sh", "#!/bin/sh\n")] {
            try? Data(content.utf8).write(to: tmp.appendingPathComponent(name))
        }
        let rules: [(String, LinkAction)] = [
            (Schemes.docBase + "run.command", .reveal(tmp.appendingPathComponent("run.command").standardizedFileURL)),
            (Schemes.docBase + "app.sh", .reveal(tmp.appendingPathComponent("app.sh").standardizedFileURL)),
            (Schemes.docBase + "note.md", .openDocument(tmp.appendingPathComponent("note.md").standardizedFileURL)),
            (Schemes.docBase + "pic.png", .openViewer(tmp.appendingPathComponent("pic.png").standardizedFileURL)),
            (Schemes.docBase + "../../etc/hosts", .ignore),
            (Schemes.docBase + "missing.md", .ignore),
            ("file://" + tmp.appendingPathComponent("run.command").path, .ignore),
            ("javascript:alert(1)", .ignore),
            ("x-apple.systempreferences:", .ignore),
            ("https://example.com/", .external(URL(string: "https://example.com/")!)),
            ("mailto:?subject=hello", .external(URL(string: "mailto:?subject=hello")!)),
        ]
        var badRule = ""
        for (href, want) in rules {
            let got = LinkPolicy.decide(href, documentFolder: tmp)
            if got != want && !(href.contains("etc/hosts") && got != .openDocument(URL(fileURLWithPath: "/etc/hosts"))) {
                badRule = "\(href) -> \(got)"
            }
        }
        // ../../etc/hosts leaves the document folder: it may at most be revealed, never opened or run.
        let escape = LinkPolicy.decide(Schemes.docBase + "../../../../../../etc/hosts", documentFolder: tmp)
        check("links: programs only shown in the Finder, nothing else opens", badRule.isEmpty, badRule)
        check("links: a path out of the folder is never opened", escape == .ignore || { if case .reveal = escape { return true }; return false }(),
              "\(escape)")

        // Save keeps BOM and CRLF.
        let crlfFile = tmp.appendingPathComponent("crlf.md")
        let original = Data([0xEF, 0xBB, 0xBF] + Array("# Title\r\n\r\nSome *text* with __bold__.\r\n\r\n- one\r\n- two\r\n".utf8))
        try? original.write(to: crlfFile)
        await d.load(crlfFile)
        await d.save(as: false)
        let back = (try? Data(contentsOf: crlfFile)) ?? Data()
        check("save: BOM and CRLF written back byte for byte", back == original,
              String(decoding: back.prefix(80), as: UTF8.self))

        // Live reload.
        let live = tmp.appendingPathComponent("live.md")
        try? Data("# One\n\nfirst\n".utf8).write(to: live)
        await d.load(live)
        let side = tmp.appendingPathComponent(".live.md.tmp")
        try? Data("# Two\n\nsecond\n".utf8).write(to: side)
        _ = try? fm.replaceItemAt(live, withItemAt: side)
        var ok = await wait(3) { await markdown(d).contains("Two") }
        let md1 = await markdown(d)
        check("live reload: save by replacing the file", ok && !d.model.dirty, md1)
        try? fm.removeItem(at: live)
        try? await Task.sleep(nanoseconds: 150_000_000)
        try? Data("# Three\n\nthird\n".utf8).write(to: live)
        ok = await wait(3) { await markdown(d).contains("Three") }
        let md2 = await markdown(d)
        check("live reload: delete and create again", ok && !d.model.dirty, md2)
        if let h = try? FileHandle(forWritingTo: live) { h.seekToEndOfFile(); h.write(Data("\nfourth line\n".utf8)); try? h.close() }
        ok = await wait(3) { await markdown(d).contains("fourth line") }
        let md3 = await markdown(d)
        check("live reload: plain write", ok && !d.model.dirty, md3)
        // Several quick saves: the last one is what shows.
        for i in 1 ... 6 { try? Data("# Burst \(i)\n".utf8).write(to: live); try? await Task.sleep(nanoseconds: 20_000_000) }
        ok = await wait(3) { await markdown(d).contains("Burst 6") }
        let md4 = await markdown(d)
        check("live reload: a burst of saves ends with the last one", ok, md4)
        // With unsaved changes the window keeps its text (a question is asked instead).
        await d.web.call("mdApp.setLocked(false); mdApp.focus(); mdApp.insertText('local edit ')")
        _ = await wait(2) { d.model.dirty }
        try? Data("# Outside\n".utf8).write(to: live)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let kept = await markdown(d)
        check("live reload: unsaved changes are not overwritten", d.model.dirty && kept.contains("local edit") && !kept.contains("Outside"), kept)
        d.window?.attachedSheet.map { d.window?.endSheet($0, returnCode: .alertSecondButtonReturn) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        d.model.dirty = false

        // Export.
        await d.loadText("# Exported\n\nA paragraph with `code`.\n\n<script>alert(1)</script>\n", sample: false)
        let out = tmp.appendingPathComponent("out.html")
        d.exportTo(out)
        ok = await wait(5) { fm.fileExists(atPath: out.path) }
        let exported = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        check("export: HTML with the text and no scripts", ok && exported.contains("Exported") && exported.contains("markdown-body")
              && !exported.lowercased().contains("<script"), String(exported.suffix(200)))

        FileHandle.standardError.write(Data((failures == 0 ? "self-test: all passed\n" : "self-test: \(failures) failed\n").utf8))
        try? fm.removeItem(at: tmp)
        exit(failures == 0 ? 0 : 1)
    }
}
