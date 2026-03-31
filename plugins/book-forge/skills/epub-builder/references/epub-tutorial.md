# Building an ePub E-Book: End-to-End Tutorial

A step-by-step walkthrough from raw Markdown files to a finished, validated `.epub` file
ready to load on any e-reader. This tutorial uses a concrete example project so you have
something real to run at each step.

For the reasoning behind every decision made here — why headings must be hierarchical, how
image paths work, what each pandoc flag does — see the companion reference:
`@epub-creation-guide.md`.

---

## What You Will Build

A three-chapter technical book with:

- A title page and copyright page
- A numbered, clickable Table of Contents
- Embedded images with correct paths
- A minimal stylesheet tuned for e-ink readers
- A cover thumbnail shown in your e-reader's library

By the end of this tutorial you will have a single `my-book.epub` file ready to sideload.

---

## Step 1 — Install Pandoc

You need **pandoc 3.0 or later**. Earlier versions do not have the `--split-level` flag.

**macOS (Homebrew):**

```bash
brew install pandoc
```

**Ubuntu / Debian:**

```bash
sudo apt-get install pandoc
```

**Windows:** Download the installer from [pandoc.org/installing.html](https://pandoc.org/installing.html).

Verify the version:

```bash
pandoc --version
# First line should read: pandoc 3.x.x
```

If the version is below 3.0, upgrade before continuing.

---

## Step 2 — Set Up the Project Directory

Create the following structure. You can start with just the Markdown files and add the
rest as you go through the tutorial.

```
my-book/
├── chapters/
│   ├── intro.md
│   ├── ch1-basics.md
│   ├── ch1-advanced.md
│   └── ch2-reference.md
├── img/
│   └── diagram.png
├── epub-style.css          ← copy from @epub-style.css
├── toc.json                ← you will create this in Step 4
├── build-epub.py           ← you will create this in Step 5
└── cover.png               ← optional; 600×900 px recommended
```

Copy `epub-style.css` from the companion file `@epub-style.css` into your project root.
If you do not have it, the build will still work — pandoc will use its built-in default
styles. Add it when you want consistent e-ink-optimised typography.

---

## Step 3 — Prepare Your Markdown Files

### Rule: one H1 per file, correct hierarchy

Every source file must begin with an H1. Subheadings go at H2, subsections at H3.
**Never skip a level** (H1 → H3 without H2 breaks TOC nesting).

Create the four chapter files with the following content (or adapt your own):

**`chapters/intro.md`**

```markdown
# Introduction

Welcome to the book. This chapter covers the background you need before diving in.

## Why This Topic Matters

E-books are increasingly the primary reading format for technical content.

## Scope of This Book

This book covers beginner through advanced usage.
```

**`chapters/ch1-basics.md`**

```markdown
# Basics

This chapter covers fundamental concepts.

## Core Concepts

Every system has a few ideas worth understanding deeply.

## Getting Started

Here is how you begin.

![System diagram](../img/diagram.png)
```

**`chapters/ch1-advanced.md`**

```markdown
# Advanced Usage

This chapter builds on the basics.

## Configuration

The system has several configuration options.

## Troubleshooting

Common problems and their solutions.
```

**`chapters/ch2-reference.md`**

```markdown
# Reference

A comprehensive reference for all options.

## Option Index

| Option | Default | Description |
|---|---|---|
| `--verbose` | false | Enable verbose output |
| `--timeout` | 30 | Request timeout in seconds |
```

### Check: does every file start with H1?

Before moving on, confirm each file starts with `# Title` (H1). Files that start with H2
become silent appendages to the previous chapter — no error, just wrong structure.

---

## Step 4 — Create the TOC Configuration

The TOC config is a JSON file that tells the build script:

- Which files to include and in what order
- Whether each file is a top-level chapter (`depth: 0`) or a subchapter (`depth: 1`)

Create `toc.json` in your project root:

```json
[
    {"title": "Introduction",   "file": "chapters/intro.md",         "depth": 0},
    {"title": "Basics",         "file": "chapters/ch1-basics.md",    "depth": 0},
    {"title": "Advanced Usage", "file": "chapters/ch1-advanced.md",  "depth": 1},
    {"title": "Reference",      "file": "chapters/ch2-reference.md", "depth": 0}
]
```

**What `depth` controls:**

- `depth: 0` — the file's H1 stays as H1 (top-level chapter)
- `depth: 1` — the file's H1 becomes H2 (subchapter under the previous chapter)
- `depth: 2` — the file's H1 becomes H3 (sub-subchapter)

In this example, "Advanced Usage" is a subchapter of "Basics": its `# Advanced Usage`
heading will become `## Advanced Usage` in the final book. Its internal `## Configuration`
heading becomes `### Configuration`, and so on.

**Result in the TOC:**

```
1  Introduction
2  Basics
   2.1  Advanced Usage
3  Reference
```

> If you have a section that exists in your outline but has no file yet, add it to
> `toc.json` anyway — the script will inject a placeholder heading to preserve the
> hierarchy.

---

## Step 5 — Create the Build Script

Create `build-epub.py` in your project root:

```python
#!/usr/bin/env python3
"""Build an ePub from a directory of Markdown files with a TOC config."""

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent
TOC_PATH     = PROJECT_ROOT / "toc.json"
CSS_PATH     = PROJECT_ROOT / "epub-style.css"
OUTPUT_PATH  = PROJECT_ROOT / "my-book.epub"
COVER_IMAGE  = PROJECT_ROOT / "cover.png"   # remove this line if you have no cover

# ── Book metadata ────────────────────────────────────────────────────────────
TITLE          = "My Book Title"
AUTHOR         = "Author Name"
LANG           = "en"
COPYRIGHT_YEAR = "2025"


def load_toc(toc_path: Path) -> list[dict]:
    return json.loads(toc_path.read_text(encoding="utf-8"))


def shift_headings(content: str, levels: int) -> str:
    if levels == 0:
        return content
    def replace(m):
        return "#" * min(6, len(m.group(1)) + levels) + m.group(2)
    return re.sub(r'^(#{1,6})([ \t].+)$', replace, content, flags=re.MULTILINE)


def ensure_h1(content: str, title: str) -> str:
    if not re.match(r'^# [^#\n]', content.lstrip('\n')):
        return f"# {title}\n\n{content}"
    return content


def rewrite_image_paths(content: str, source_dir: str, resource_path: str) -> str:
    def fix(m):
        alt, path = m.group(1), m.group(2)
        if path.startswith(('http://', 'https://', '/')):
            return m.group(0)
        abs_path = os.path.normpath(os.path.join(source_dir, path))
        rel_path = os.path.relpath(abs_path, resource_path).replace(os.sep, '/')
        return f'![{alt}]({rel_path})'
    return re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', fix, content)


def build():
    entries = load_toc(TOC_PATH)
    parts = []

    # Copyright page — unnumbered and unlisted so it has no chapter number and
    # does not appear as a TOC entry
    parts.append(
        f"# Copyright {{.unnumbered .unlisted}}\n\n"
        f"© {COPYRIGHT_YEAR} {AUTHOR}. All rights reserved.\n\n"
    )

    for entry in entries:
        filepath = PROJECT_ROOT / entry["file"]
        depth = entry.get("depth", 0)
        title = entry["title"]

        if not filepath.exists():
            parts.append(f"# {title}\n\n")
            continue

        content = filepath.read_text(encoding="utf-8")
        content = rewrite_image_paths(content, str(filepath.parent), str(PROJECT_ROOT))
        content = ensure_h1(content, title)
        content = shift_headings(content, depth)
        parts.append(content.strip() + "\n\n")

    combined = "\n".join(parts)

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".md", encoding="utf-8", delete=False
    ) as tmp:
        tmp.write(combined)
        tmp_path = tmp.name

    cmd = [
        "pandoc", tmp_path,
        "--from=markdown-yaml_metadata_block",
        "--to=epub3",
        f"--output={OUTPUT_PATH}",
        f"--metadata=title:{TITLE}",
        f"--metadata=author:{AUTHOR}",
        f"--metadata=lang:{LANG}",
        f"--metadata=date:{COPYRIGHT_YEAR}",
        f"--metadata=rights:© {COPYRIGHT_YEAR} {AUTHOR}",
        "--toc",
        "--toc-depth=3",
        "--split-level=2",
        "--number-sections",
        f"--css={CSS_PATH}",
        f"--resource-path={PROJECT_ROOT}",
    ]

    cover = COVER_IMAGE  # remove this block if you have no cover image
    if cover.exists():
        cmd.append(f"--epub-cover-image={cover}")

    try:
        subprocess.run(cmd, check=True)
        print(f"Built: {OUTPUT_PATH}")
    finally:
        os.unlink(tmp_path)


if __name__ == "__main__":
    build()
```

**Before running:** update the five constants at the top of the script:

```python
TITLE          = "My Book Title"
AUTHOR         = "Author Name"
LANG           = "en"
COPYRIGHT_YEAR = "2025"
```

---

## Step 6 — Run the First Build

From your project root:

```bash
python build-epub.py
```

**Expected output:**

```
Built: /path/to/my-book/my-book.epub
```

If pandoc prints warnings, read them — they usually point to a real problem. The one
warning you can ignore safely is:

```
[WARNING] Could not find image ...
```

…only if that image is intentionally absent. For images you expect to be embedded, this
warning means a path is wrong (see Step 7).

**If you get a YAML parse error:**

```
Error parsing YAML metadata at .../tmp*.md (line N, column 1):
mapping values are not allowed in this context
```

One of your Markdown files contains a `---` horizontal rule. The
`--from=markdown-yaml_metadata_block` flag in the script already disables the problematic
extension — if you still see this error, check that the flag is present in your `cmd`
list.

Open `my-book.epub` on your e-reader or in a desktop reader (Calibre, Apple Books,
Thorium). You should see:

- A title page with your book title and author
- A clickable, numbered Table of Contents
- Four numbered chapters with correct nesting (2.1 Advanced Usage under chapter 2)

---

## Step 7 — Fix Images

Image path issues are the most common cause of broken ePubs. The script handles them
automatically — but only for standard Markdown image syntax: `![alt text](path/to/img)`.

### Confirm the image reference is correct

In `chapters/ch1-basics.md`, the image is referenced as:

```markdown
![System diagram](../img/diagram.png)
```

This path is relative to the file's own location (`chapters/`), so `../img/` correctly
resolves to `my-book/img/`. The script rewrites it before passing to pandoc.

### Confirm the image exists

```bash
ls img/
# diagram.png
```

If the image is missing, pandoc will embed nothing and print a warning. Add a real PNG or
placeholder and rebuild.

### Check the result

Open the ePub and navigate to the "Basics" chapter. The diagram should appear inline.

If the image still does not render:

1. Check that `resource_path` in the script points to your project root (the directory
   that contains `img/`)
2. Check that the relative path in the Markdown file resolves to an existing file when
   read from that file's directory

---

## Step 8 — Add a Cover Image

A cover image appears as a thumbnail in your e-reader's library and as the first visual
in the book.

Requirements:

- Format: PNG or JPEG
- Recommended size: 600×900 px (2:3 ratio, portrait)
- File name: `cover.png` (or update `COVER_IMAGE` in the script)

The script already checks `if cover.exists()` before adding it to the pandoc command —
no changes needed.

Rebuild and check your e-reader's library view. The cover should appear as a thumbnail.

---

## Step 9 — Validate

Validation catches structural problems that readers may reject or render incorrectly.

Install [EPUBCheck](https://www.w3.org/publishing/epubcheck/) (requires Java):

```bash
# Download epubcheck-5.x.x.zip from github.com/w3c/epubcheck/releases
# Unzip and run:
java -jar epubcheck.jar my-book.epub
```

**What to look for:**

| Error | Cause | Fix |
|---|---|---|
| `Duplicate ID` | Two headings produce the same slug (e.g., two sections titled "Overview") | Rename one, or assign an explicit ID: `## Overview {#overview-intro}` |
| `Missing alt text` | Image `![](path)` has no alt text | Add descriptive alt: `![System diagram](path)` |
| `Invalid XHTML` | Raw HTML in your Markdown has unclosed tags or invalid attributes | Fix or remove the raw HTML |

A clean EPUBCheck run with zero errors means the file will open correctly on any
standards-compliant reader.

---

## Step 10 — Iterate

### Adjusting chapter structure

Edit `toc.json` to reorder, add, or remove chapters. You do not need to touch the source
files — structure comes from the config, not the filenames.

To promote "Advanced Usage" back to a top-level chapter:

```json
{"title": "Advanced Usage", "file": "chapters/ch1-advanced.md", "depth": 0}
```

Rebuild and the TOC updates automatically.

### Excluding a section temporarily

Remove its entry from `toc.json`. The file stays on disk, unmodified.

### Adjusting the copyright page

To remove the copyright page from the TOC but keep it in the book, the script already
uses `{.unnumbered .unlisted}` on the copyright heading. To remove the page entirely,
delete the `parts.append(...)` block that adds it.

### Adjusting styles

Edit `epub-style.css` and rebuild. The most impactful changes for readability:

- **`body line-height`** — increase toward `2.0` if the text feels too dense
- **`body font-size`** — leave this at `1em`; adjust via your e-reader's font size
  setting instead
- **`pre font-size`** — reduce to `0.78em` if code blocks feel too wide for your screen

---

## Quick-Reference Checklist

Before calling a build done, run through this list:

- [ ] Every source file starts with H1
- [ ] No heading levels are skipped (H1 → H3 without H2)
- [ ] `toc.json` lists all chapters in the correct order with correct `depth` values
- [ ] All image paths in Markdown are relative to the file's own directory
- [ ] `cover.png` exists (if you want a library thumbnail)
- [ ] Metadata constants updated in `build-epub.py` (title, author, year)
- [ ] Build runs with no errors
- [ ] EPUBCheck passes with zero errors

---

## Where to Go Next

The companion reference `@epub-creation-guide.md` covers:

- Footnotes and cross-references
- TeX math handling
- Internal links between chapters
- Large image optimisation
- Encoding and BOM issues
- The full `rewrite_image_paths` API and its constraints for multi-directory projects
