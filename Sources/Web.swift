// Gryphmark: the editor page in a WKWebView, and what it may reach.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// The page (web/) is the one of the Windows version. On Windows it is served from
// https://app.local/ and the document's folder from https://doc.local/; here two private schemes
// do the same: gm-app://app/ serves the app's own web folder and gm-doc://doc/ the folder of the
// open document, so relative pictures show. Nothing else can be loaded: every other navigation
// is cancelled and handed to the link policy (LinkPolicy.swift). The page talks to the app through
// window.chrome.webview.postMessage, which a small script maps to WebKit's message handler.

import AppKit
import WebKit

enum Schemes {
    static let app = "gm-app"
    static let doc = "gm-doc"
    static let appBase = "gm-app://app/"
    static let docBase = "gm-doc://doc/"
}

/// Serves files under `root` for one scheme, never outside it.
final class FolderSchemeHandler: NSObject, WKURLSchemeHandler {
    var root: URL?
    /// The page's own files (index.html, app.js) are rewritten so their https://app.local/
    /// addresses point to gm-app://app/; the libraries are served untouched.
    let rewriteIndex: Bool

    init(root: URL?, rewriteIndex: Bool) {
        self.root = root
        self.rewriteIndex = rewriteIndex
    }

    static let types: [String: String] = [
        "html": "text/html", "js": "text/javascript", "css": "text/css", "woff2": "font/woff2", "png": "image/png",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp",
        "bmp": "image/bmp", "json": "application/json", "txt": "text/plain", "md": "text/plain",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let root = root?.standardizedFileURL else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let rel = (url.path.removingPercentEncoding ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = root.appendingPathComponent(rel).standardizedFileURL.resolvingSymlinksInPath()
        let base = root.resolvingSymlinksInPath().path
        guard file.path == base || file.path.hasPrefix(base + "/"),
              var data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let ext = file.pathExtension.lowercased()
        if rewriteIndex && (ext == "html" || ext == "js" && !rel.hasPrefix("lib/")), let s = String(data: data, encoding: .utf8) {
            data = Data(s.replacingOccurrences(of: "https://app.local/", with: Schemes.appBase).utf8)
        }
        let type = FolderSchemeHandler.types[ext] ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type, "Content-Length": "\(data.count)"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// One editor page. Messages from the page go to `onMessage`; links to `onLink`.
final class EditorWeb: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let view: WKWebView
    let docHandler = FolderSchemeHandler(root: nil, rewriteIndex: false)
    var onMessage: (([String: Any]) -> Void)?
    var onLink: ((String) -> Void)?
    var onFileDrop: ((URL) -> Void)?

    static var webFolder: URL? { Bundle.main.url(forResource: "web", withExtension: nil) }

    override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(FolderSchemeHandler(root: EditorWeb.webFolder, rewriteIndex: true), forURLScheme: Schemes.app)
        config.setURLSchemeHandler(docHandler, forURLScheme: Schemes.doc)
        let shim = """
            window.chrome = { webview: { postMessage: function (m) { window.webkit.messageHandlers.host.postMessage(m); } } };
            """
        config.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.preferences.isElementFullscreenEnabled = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Live reload happens while the user works in another app (often the AI assistant that
        // edits the file): the page must keep its timers running when the window is behind.
        config.preferences.inactiveSchedulingPolicy = .none
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(WeakHandler(self), name: "host")
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsMagnification = false
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: URL(string: Schemes.appBase + "index.html")!))
    }

    /// The folder relative pictures and links of the document come from (nil: none).
    func setDocumentFolder(_ dir: URL?) { docHandler.root = dir }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if let d = message.body as? [String: Any] { onMessage?(d) }
    }

    /// Runs `mdApp.<call>` with JSON-safe arguments and returns its result.
    @discardableResult
    func call(_ body: String, _ args: [String: Any] = [:]) async -> Any? {
        try? await view.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page)
    }

    // Only the app's own page loads in the view. A drop of a file arrives as a navigation to it.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == Schemes.app && action.targetFrame?.isMainFrame == true && url.path == "/index.html" {
            decisionHandler(.allow); return
        }
        if url.scheme == Schemes.app || url.scheme == Schemes.doc, action.targetFrame?.isMainFrame == false {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if url.isFileURL { onFileDrop?(url) } else { onLink?(url.absoluteString) }
    }

    // window.open and target=_blank: never a new window, only the link policy.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url { onLink?(u.absoluteString) }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onMessage?(["type": "crashed"])
    }
}

/// WKUserContentController keeps its handlers strongly; this breaks the cycle.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
