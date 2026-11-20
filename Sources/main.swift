// Vigia: entry point.
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 10, 2026
// SPDX-License-Identifier: GPL-2.0-only

import AppKit

// The settings kept under the name this app had up to 2.2.1 come over before anything reads them (Migration.swift).
Migration.settings()

// vigia --make-instance "Name" …: makes a dedicated instance without opening a window (Instances.swift).
if CommandLine.arguments.contains("--make-instance") { Instance.makeFromCommandLine(CommandLine.arguments) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
