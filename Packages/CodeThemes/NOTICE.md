# CodeThemes notices

Only color values were taken from the themes below; no theme files are included. The values were
read from each theme's VS Code theme as packaged by
[shikijs/textmate-grammars-themes](https://github.com/shikijs/textmate-grammars-themes) (`tm-themes`,
MIT, Copyright (c) Anthony Fu), which copies them unchanged from the upstream repositories listed
here. Every upstream theme is MIT licensed. The Native theme is original.

| Theme in CodeThemes | Upstream | Copyright |
| --- | --- | --- |
| Catppuccin Latte, Macchiato, Mocha | [catppuccin/vscode](https://github.com/catppuccin/vscode) | Copyright (c) 2021 Catppuccin |
| Dracula | [dracula/visual-studio-code](https://github.com/dracula/visual-studio-code) | Copyright (c) 2016 Dracula Theme |
| Nord | [nordtheme/visual-studio-code](https://github.com/nordtheme/visual-studio-code) | Copyright (c) 2016-present Sven Greb |
| Tokyo Night | [enkia/tokyo-night-vscode-theme](https://github.com/enkia/tokyo-night-vscode-theme) | Copyright (c) 2018-present Enkia |
| Gruvbox Dark (medium) | [jdinhify/vscode-theme-gruvbox](https://github.com/jdinhify/vscode-theme-gruvbox), palette by [morhetz/gruvbox](https://github.com/morhetz/gruvbox) | Copyright (c) 2017 JD |
| Solarized (light and dark) | [microsoft/vscode](https://github.com/microsoft/vscode) `theme-solarized-*`, palette by [Ethan Schoonover](https://ethanschoonover.com/solarized/) | Copyright (c) 2015-present Microsoft Corporation |
| GitHub (light and dark) | [primer/github-vscode-theme](https://github.com/primer/github-vscode-theme) | Copyright (c) 2020 Primer |
| Atom One, light | [akamud/vscode-theme-onelight](https://github.com/akamud/vscode-theme-onelight) | Copyright (c) 2015 Mahmoud Ali |
| Atom One, dark | [Binaryify/OneDark-Pro](https://github.com/Binaryify/OneDark-Pro) | Copyright (c) 2013-2022 Binaryify |
| Rosé Pine (main and Dawn) | [rose-pine/vscode](https://github.com/rose-pine/vscode) | Copyright (c) 2021 Rosé Pine |

Where a theme does not define a role (for example a changed-line background, which VS Code themes
have no key for), the value is derived from that theme's own colors and marked in the source.

## Tree-sitter

Highlighting links the tree-sitter runtime, its Swift API and the grammars below as Swift packages
(versions in `Package.swift`), and `Sources/CodeThemes/Queries` holds copies of each grammar's
highlight and injection queries from the same release. Each copied file names its source in its
first line and says what changed, if anything.

| Component | Upstream | License | Copyright |
| --- | --- | --- | --- |
| Runtime | [tree-sitter/tree-sitter](https://github.com/tree-sitter/tree-sitter) | MIT | Copyright (c) 2018-2024 Max Brunsfeld |
| Swift API | [tree-sitter/swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter) (SwiftTreeSitter) | BSD-3-Clause | Copyright (c) 2021, Chime |
| Swift | [alex-pinkus/tree-sitter-swift](https://github.com/alex-pinkus/tree-sitter-swift) | MIT | Copyright (c) 2021 alex-pinkus |
| TypeScript, TSX | [tree-sitter/tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) | MIT | Copyright (c) 2017 Max Brunsfeld |
| JavaScript | [tree-sitter/tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) | MIT | Copyright (c) 2014 Max Brunsfeld |
| Python | [tree-sitter/tree-sitter-python](https://github.com/tree-sitter/tree-sitter-python) | MIT | Copyright (c) 2016 Max Brunsfeld |
| Rust | [tree-sitter/tree-sitter-rust](https://github.com/tree-sitter/tree-sitter-rust) | MIT | Copyright (c) 2017 Maxim Sokolov |
| Go | [tree-sitter/tree-sitter-go](https://github.com/tree-sitter/tree-sitter-go) | MIT | Copyright (c) 2014 Max Brunsfeld |
| JSON | [tree-sitter/tree-sitter-json](https://github.com/tree-sitter/tree-sitter-json) | MIT | Copyright (c) 2014 Max Brunsfeld |
| Bash | [tree-sitter/tree-sitter-bash](https://github.com/tree-sitter/tree-sitter-bash) | MIT | Copyright (c) 2017 Max Brunsfeld |
| YAML | [tree-sitter-grammars/tree-sitter-yaml](https://github.com/tree-sitter-grammars/tree-sitter-yaml) | MIT | Copyright (c) 2024 tree-sitter-grammars contributors |
| TOML | [tree-sitter-grammars/tree-sitter-toml](https://github.com/tree-sitter-grammars/tree-sitter-toml) | MIT | Copyright (c) Ika |
| HTML | [tree-sitter/tree-sitter-html](https://github.com/tree-sitter/tree-sitter-html) | MIT | Copyright (c) 2014 Max Brunsfeld |
| CSS | [tree-sitter/tree-sitter-css](https://github.com/tree-sitter/tree-sitter-css) | MIT | Copyright (c) 2018 Max Brunsfeld |
| Markdown | [tree-sitter-grammars/tree-sitter-markdown](https://github.com/tree-sitter-grammars/tree-sitter-markdown) | MIT | Copyright (c) 2021 Matthias Deiml |
| C | [tree-sitter/tree-sitter-c](https://github.com/tree-sitter/tree-sitter-c) | MIT | Copyright (c) 2014 Max Brunsfeld |
| Java | [tree-sitter/tree-sitter-java](https://github.com/tree-sitter/tree-sitter-java) | MIT | Copyright (c) 2017 Ayman Nadeem |

The Markdown queries say they derive from
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (Apache-2.0), which the
grammar's repository redistributes under its own MIT license.
