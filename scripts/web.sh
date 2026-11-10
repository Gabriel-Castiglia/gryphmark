#!/bin/zsh
# web.sh: rebuilds the web bundle (web/lib) from _npm, as the Windows version does.
#
# Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
# Date: November 10, 2026
# SPDX-License-Identifier: GPL-2.0-only
#
# This program is free software: you can redistribute it and/or modify it under the terms of
# the GNU General Public License, version 2, as published by the Free Software Foundation.
# It is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.
#
# Needs Node.js with npm. The bundle in the repository was made this way, with the exact
# versions of _npm/package-lock.json; the app only needs web/, so building it is optional.

set -euo pipefail
RAIZ="${0:A:h:h}"
cd "$RAIZ/_npm"
command -v npm >/dev/null || { echo "npm is missing (Node.js)" >&2; exit 1 }
npm ci --silent
W="$RAIZ/web/lib"
mkdir -p "$W/fonts"
npx esbuild entry.js --bundle --minify --format=iife --outfile="$W/bundle.js"
nm=node_modules
cp $nm/@toast-ui/editor/dist/toastui-editor.css $nm/@toast-ui/editor/dist/theme/toastui-editor-dark.css \
   $nm/@toast-ui/editor-plugin-code-syntax-highlight/dist/toastui-editor-plugin-code-syntax-highlight.css \
   $nm/github-markdown-css/github-markdown-light.css $nm/github-markdown-css/github-markdown-dark.css "$W/"
cp $nm/highlight.js/styles/github.min.css "$W/hljs-light.css"
cp $nm/highlight.js/styles/github-dark.min.css "$W/hljs-dark.css"
cp $nm/mermaid/dist/mermaid.min.js $nm/katex/dist/katex.min.css "$W/"
cp $nm/katex/dist/fonts/*.woff2 "$W/fonts/"
echo "web bundle rebuilt in web/lib"
