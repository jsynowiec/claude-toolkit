---
name: epub-builder
description: Builds ePub 3 e-books from Markdown sources using pandoc. Generates a project-specific Python build script, embeds a production-ready e-ink stylesheet, and compiles chapters into a validated .epub file. Use when creating an epub, building an ebook, converting markdown to epub, generating an e-book, packaging chapters as an epub, or turning documentation into an ebook.
user-invocable: false
allowed-tools: Read, Glob, Grep, Bash, Write
---

## Prerequisites

Verify before starting:

```bash
pandoc --version   # Must be >= 3.0 (--split-level flag requires it)
python3 --version  # Must be >= 3.10
```

If pandoc is missing or below 3.0: `brew install pandoc` (macOS) or `apt-get install pandoc` (Linux).

Optional: EPUBCheck for validation (`java -jar epubcheck.jar`). Requires Java.

## Workflow

### Step 1 — Discover the project

If the user specifies source files, a directory, or a glob pattern, use those directly. If they point to an existing manifest (sidebar config, `_toc.yml`, navigation JSON), read it to derive the file list and reading order.

Otherwise, use Glob to find Markdown files. Look for naming conventions that imply order (numeric prefixes, directory hierarchy) to derive reading order. If ambiguous, ask the user which files to include and in what order.

Verify every source file starts with H1 (`# Title`). Files without H1 become silent appendages to the previous chapter — no error, just wrong structure.

### Step 2 — Collect metadata

Ask the user for:

- **Title** and **author** (required)
- **Language** (default: `en`)
- **Copyright year** (default: current year)
- **Cover image path** (optional, PNG or JPEG, 600x900 px recommended)

### Step 3 — Create toc.json

If the user specifies chapter order, nesting, or which files are subchapters, use that directly to build the TOC. If an existing toc.json or equivalent manifest already exists in the project, read and adapt it rather than creating from scratch.

Otherwise, derive the order from Step 1 (file naming, directory structure, or navigation manifest) and confirm with the user before proceeding.

Write `toc.json` in the project root. Use the TOC config format documented in `references/epub-creation-guide.md` (search for "TOC Config Format"):

```json
[
    {"title": "Introduction", "file": "chapters/intro.md", "depth": 0},
    {"title": "Getting Started", "file": "chapters/start.md", "depth": 1}
]
```

`depth` controls heading shifts: 0 = chapter (H1 stays H1), 1 = subchapter (H1 → H2), 2 = sub-subchapter (H1 → H3).

### Step 4 — Generate build script and stylesheet

Copy `references/epub-style.css` into the project root as `epub-style.css`.

Generate a project-specific `build-epub.py` using the complete build script pattern from `references/epub-creation-guide.md` (search for "The Script"). Adapt:

- Path constants to match the project's directory layout
- Metadata constants from Step 2
- Any project-specific preprocessing (MDX conversion, custom image syntax, etc.)

Do NOT use a generic one-size-fits-all script. Each book has different paths, metadata, and structure.

### Step 5 — Build and validate

```bash
python3 build-epub.py
```

If pandoc warns or fails, consult `references/epub-creation-guide.md` for the relevant gotcha (YAML `---` errors, missing images, heading hierarchy issues).

If EPUBCheck is available:

```bash
java -jar epubcheck.jar <output>.epub
```

For common validation errors and fixes, see the "Validation" section of `references/epub-creation-guide.md`.

## Reference Files

Use the comprehensive build guide in `references/epub-creation-guide.md` for pandoc flags, heading hierarchy rules, image path rewriting functions, the YAML `---` gotcha, and the complete Python build script pattern.

Use the step-by-step tutorial in `references/epub-tutorial.md` for the recommended project directory layout, TOC configuration examples, and the build-test-iterate workflow.

Use `references/epub-style.css` as the production-ready stylesheet. Copy it into the user's project. It is optimised for e-ink readers with relative units, high line-height, and safe CSS selectors.

## Output Format

```
## Build Complete
- **Output:** <path to .epub file>
- **Chapters:** <count> chapters from <count> source files
- **Stylesheet:** epub-style.css (e-ink optimised)
- **Validation:** <EPUBCheck result or "skipped — EPUBCheck not installed">

## Files Created
- `toc.json` — chapter ordering and depth configuration
- `build-epub.py` — project-specific build script (re-run with `python3 build-epub.py`)
- `epub-style.css` — e-ink optimised stylesheet
- `<output>.epub` — the final e-book

## Next Steps
- Edit `toc.json` to reorder or add chapters, then re-run `python3 build-epub.py`
- Open the .epub in Calibre, Apple Books, or sideload to your e-reader
```

## Rules

- Always consult `references/epub-creation-guide.md` for pandoc flags. Do not guess from training data.
- Always use `--from=markdown-yaml_metadata_block` to disable YAML metadata parsing. Without this, `---` horizontal rules in content cause cryptic parse errors.
- Always rewrite relative image paths before combining files. Run `rewrite_image_paths` after any format-specific syntax conversion, and only once.
- Every source file must start with H1. If one does not, prepend a title from toc.json using `ensure_h1`.
- Never skip heading levels (H1 directly to H3). Shift headings based on `depth` in toc.json.
- Copy `references/epub-style.css` into the project directory rather than referencing the plugin path. The built epub must be self-contained.
- When using `--number-sections` with `--toc`, the reference stylesheet suppresses `<ol>` list markers in `nav#toc` to prevent double numbering. If using a custom stylesheet, it must include `nav#toc ol { list-style-type: none; }` or the TOC will show both list markers and section numbers.
