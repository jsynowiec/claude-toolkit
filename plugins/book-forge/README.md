# book-forge

A Claude Code plugin for building professionally structured ePub 3 e-books from Markdown sources using pandoc.

## Requirements

- [pandoc](https://pandoc.org/) >= 3.0 — the core conversion engine. Install with `brew install pandoc` (macOS) or `apt-get install pandoc` (Linux).
- Python >= 3.10 — runs the generated build script.
- [EPUBCheck](https://www.w3.org/publishing/epubcheck/) (optional) — validates the output against the ePub 3 spec. Requires Java.

## Skills

| Skill | Purpose |
|-------|---------|
| **epub-builder** | Discovers project Markdown files, generates a project-specific Python build script and e-ink stylesheet, then compiles everything into a validated .epub file |

## License

[MIT](../../LICENSE)
