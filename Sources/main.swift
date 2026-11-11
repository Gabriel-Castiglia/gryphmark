// Gryphmark: entry point.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only

import AppKit

// gryphmark --make-instance "Name" …: makes a dedicated instance without opening a window (Instances.swift).
if CommandLine.arguments.contains("--make-instance") { Instance.makeFromCommandLine(CommandLine.arguments) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
