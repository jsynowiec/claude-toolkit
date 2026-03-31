# Creating ePub E-Books with Pandoc

A practical guide for building well-structured ePub 3 e-books from formatted text sources
(Markdown, HTML) using pandoc. Written from hands-on experience — every gotcha listed here
caused a real build failure or rendering bug.

## Overview

An ePub is a ZIP archive containing XHTML content, a CSS stylesheet, embedded images,
navigation metadata, and a package manifest. Pandoc generates all of this from Markdown
(or HTML) input. Your job is to feed it clean, well-structured input and handle the edge
cases pandoc can't.

The pipeline:

```
Source files  →  Combine + normalize headings  →  pandoc  →  .epub
```

## Prerequisites

**Pandoc ≥ 3.0** (released 2023-01-18). The `--split-level` flag used throughout this
guide was introduced in 3.0 when it replaced the older `--epub-chapter-level`. On earlier
versions you'll get an "unrecognized option" error.

Check your version:

```bash
pandoc --version
```

## Reference Stylesheet

This guide references `@epub-style.css` — a minimal stylesheet optimised for e-ink
readers. In the context of a Claude agent skill, `@filename` means the file is attached
alongside this skill and Claude can read it directly. If you're using this guide outside
an agent context, find `epub-style.css` next to this file.

## What a Good ePub Needs

### 1. Metadata

Pandoc accepts metadata via `--metadata` flags or a YAML file (`--metadata-file`). At
minimum:

```bash
--metadata=title:"Book Title"
--metadata=author:"Author Name"
--metadata=lang:en
--metadata=date:2025
--metadata=rights:"© 2025 Author. Licensed under CC BY 4.0."
```

Optional but recommended:

```bash
--epub-cover-image=cover.png    # thumbnail shown in e-reader library
```

The cover image must be PNG or JPEG. It does not appear as a chapter — pandoc inserts it
as the ePub cover metadata.

### 2. Heading Hierarchy (Critical)

Pandoc derives the **entire** book structure — TOC, chapter splits, section numbering —
from heading levels. This is the single most important thing to get right.

**Rule: one H1 per chapter, subchapters at H2, subsections at H3.**

```markdown
# Introduction                    ← Chapter (H1)

## LLM Settings                   ← Subchapter (H2)

### Temperature                   ← Subsection (H3)

## Basics of Prompting            ← Subchapter (H2)
```

**Never skip heading levels.** H1 → H3 (skipping H2) breaks TOC nesting in most readers
and fails accessibility checks.

If your source files each start with H1 but some are subchapters, **shift their headings**
before combining:

```python
import re

def shift_headings(content: str, levels: int) -> str:
    """Increase all heading levels by `levels` (caps at H6)."""
    if levels == 0:
        return content
    def replace(m):
        hashes, rest = m.group(1), m.group(2)
        return "#" * min(6, len(hashes) + levels) + rest
    return re.sub(r'^(#{1,6})([ \t].+)$', replace, content, flags=re.MULTILINE)
```

Usage: a file at depth 1 (subchapter) gets `shift_headings(content, 1)` — its H1 becomes
H2, its H2 becomes H3, and so on.

**Missing titles:** If a source file doesn't start with H1, prepend one from your
metadata/TOC. Otherwise the file's content floats as an untitled subsection of the
previous chapter — silently wrong with no warning.

```python
def ensure_h1(content: str, title: str) -> str:
    if not re.match(r'^# [^#\n]', content.lstrip('\n')):
        return f"# {title}\n\n{content}"
    return content
```

**Synthetic chapter headers:** If a section exists in your TOC but has no corresponding
content file, inject a bare heading to preserve the hierarchy:

```python
parts.append(f"# {section_title}\n\n")
```

### 3. Chapter Splitting

Pandoc splits the ePub into separate XHTML files at heading boundaries. This controls
navigation granularity on e-readers.

```bash
--split-level=2    # Split at H1 and H2 (each subchapter = separate file)
```

| `--split-level` | Behaviour | Best for |
|---|---|---|
| `1` (default) | Split at H1 only | Books with few, large chapters |
| `2` | Split at H1 and H2 | Technical books with many sections |
| `3` | Split at H1–H3 | Reference manuals |

> **Note:** `--epub-chapter-level` is the old name, deprecated in pandoc 3.0.
> Use `--split-level` instead.

### 4. Table of Contents

```bash
--toc                # Generate a clickable TOC
--toc-depth=3        # Include H1, H2, H3 in TOC
--number-sections    # Add "1.2.3" numbering to headings
```

To exclude a section from numbering (e.g., a copyright page), append `{.unnumbered}` to
the heading. The section still appears in the TOC, just without a number:

```markdown
# Copyright {.unnumbered}

© 2025 Author Name.
```

To exclude a section from the TOC entirely, add `{.unlisted}` (can be combined with
`{.unnumbered}`):

```markdown
# Copyright {.unnumbered .unlisted}
```

Use `{.unlisted}` for front matter like copyright and dedication pages that you want in
the document but not as navigable TOC entries.

### 5. Images

**Supported formats:** PNG, JPEG, GIF, SVG. Use PNG for diagrams, JPEG for photos. SVG
scales perfectly on any screen but support varies across readers — test on your target
device before relying on it.

**Sizing:** Set `max-width: 100%` in CSS — never use fixed pixel widths. E-readers have
wildly different screen sizes. The reference stylesheet (`@epub-style.css`) handles this.

**Embedding:** Pandoc embeds all referenced images into the ePub ZIP automatically. Use
`--resource-path` to tell pandoc which directory to search:

```bash
--resource-path=/path/to/project    # pandoc searches here for image files
```

**Path resolution — the #1 source of failures:** When combining files from multiple
directories, relative image paths like `../../img/photo.png` are relative to each source
file's location. After combining into one file they point to the wrong place. You must
rewrite them to be relative to the combined document or to `--resource-path` before
passing to pandoc.

```python
import os, re

def rewrite_image_paths(content: str, source_dir: str, resource_path: str) -> str:
    """
    Rewrite relative image paths so they resolve correctly when pandoc runs.

    source_dir:    directory the source file was in (images are relative to this)
    resource_path: the single project root passed to pandoc's --resource-path;
                   also used as the base for computing relative paths in output.
                   Both roles must point to the same directory for this to work.
                   Multi-directory resource paths are not supported here.
    """
    def fix(m):
        alt, path = m.group(1), m.group(2)
        if path.startswith(('http://', 'https://', '/')):
            return m.group(0)                          # absolute — leave alone
        abs_path = os.path.normpath(os.path.join(source_dir, path))
        rel_path = os.path.relpath(abs_path, resource_path)
        # Pandoc requires forward slashes on all platforms
        rel_path = rel_path.replace(os.sep, '/')
        return f'![{alt}]({rel_path})'
    return re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', fix, content)
```

Call this per source file, passing the file's own directory as `source_dir` and the value
you'll use for `--resource-path` as `resource_path`.

**Order matters:** Run `rewrite_image_paths` **after** any pass that converts
format-specific image syntax into standard Markdown `![alt](path)`, so that those
newly-converted images get their paths fixed too. Steps that don't produce `![alt](path)`
output (heading shifts, title injection, front matter) can safely come before or after —
they don't touch image syntax.

**Alt text:** Always include it — required for accessibility and serves as fallback when
images don't render.

### 6. Stylesheet

Reference stylesheet: `@epub-style.css`

Key principles for e-ink readers:

- **Relative units only** (`em`, `%`). Never `px` for text — readers must be able to
  rescale font size.
- **Black on white.** E-ink renders everything in grayscale. Coloured text becomes grey.
- **High line-height** (`1.7–1.8`). E-ink has no subpixel rendering; tight spacing looks
  cramped.
- **`page-break-after: avoid`** on headings prevents orphaned headings at page bottoms.
- **`page-break-inside: avoid`** on `pre` and `table` keeps code blocks and tables
  together.
- **Keep selectors simple.** Many e-readers ignore `:nth-child`, `:has()`, flexbox, and
  grid. Use element, class, and basic descendant selectors for anything that must work.
  Pseudo-selectors like `:nth-child` are acceptable for non-critical polish (e.g., table
  row striping) — if ignored, the content is still readable.
- **No `position: fixed/absolute`**, no `float` for layout, no animations. These are
  ignored or break reflowable rendering.
- **`overflow-x: auto`** on `pre`. Long code lines scroll on capable readers and clip
  gracefully on others — either way they don't break the layout.

Embed the stylesheet with:

```bash
--css=/path/to/epub-style.css
```

### 7. Outgoing Links

Standard Markdown links (`[text](https://...)`) become clickable `<a href>` tags in the
ePub. No special handling needed — pandoc preserves them automatically.

### 8. Footnotes

Standard Pandoc Markdown footnote syntax works in ePub:

```markdown
The technique has known limitations.[^1]

[^1]: See Smith et al. (2023) for a full treatment.
```

Pandoc converts footnotes to ePub footnote elements (`epub:type="footnote"`), which
e-readers render as pop-ups or end-of-chapter notes depending on the device.

Inline footnotes are also supported:

```markdown
The technique has known limitations.^[See Smith et al. (2023) for a full treatment.]
```

Both styles produce identical ePub output. Use whichever keeps your source more readable.

**Footnote placement:** Pandoc collects all footnotes in a combined document and places
them at the end of the section where they appear. When using `--split-level=2`, footnotes
stay in the same XHTML file as the paragraph that references them.

### 9. Internal Cross-References

To link from one part of the book to another, use a standard Markdown fragment link:

```markdown
See [the RAG section](#retrieval-augmented-generation) for details.
```

Pandoc auto-generates heading IDs using this algorithm (from the pandoc manual):

1. Remove all formatting, links, footnotes
2. Remove all non-alphanumeric characters except underscores, hyphens, and periods
3. Replace spaces and newlines with hyphens
4. Lowercase everything
5. Strip leading characters until a letter is found

Examples: `# Retrieval Augmented Generation` → `#retrieval-augmented-generation`,
`# 3. Applications` → `#applications`.

Duplicate headings get `-1`, `-2` suffixes: two sections both titled "Overview" produce
`#overview` and `#overview-1`.

**Cross-file links in split ePubs:** Pandoc resolves fragment links across file
boundaries. A link to `#some-heading` in `ch003.xhtml` will still work from `ch010.xhtml`
even when `--split-level=2` puts them in separate XHTML files. Pandoc builds a global ID
table across all content files.

**Use explicit IDs to be safe.** If the heading text might change, assign an explicit ID
that won't:

```markdown
## Retrieval Augmented Generation {#rag}
```

Then link with `[text](#rag)`.

### 10. Front and Back Matter

A professional ePub includes at minimum:

1. **Title page** — generated automatically from `--metadata=title` and
   `--metadata=author`
2. **Copyright page** — first section in your combined document, marked `{.unnumbered}`
3. **Table of Contents** — generated by `--toc`

Optional: Dedication, Preface, Appendices, Index.

## The Pandoc Command

Putting it all together:

```bash
pandoc combined.md \
    --from=markdown-yaml_metadata_block \
    --to=epub3 \
    --output=book.epub \
    --metadata=title:"Book Title" \
    --metadata=author:"Author Name" \
    --metadata=lang:en \
    --metadata=date:2025 \
    --metadata=rights:"© 2025 Author" \
    --epub-cover-image=cover.png \
    --toc \
    --toc-depth=3 \
    --split-level=2 \
    --number-sections \
    --css=epub-style.css \
    --resource-path=/path/to/project
```

**Flags explained:**

- `--from=markdown-yaml_metadata_block` — the minus sign *disables* the
  `yaml_metadata_block` extension. See the YAML gotcha below for why this is essential.
  The `raw_html` extension (passing HTML blocks through to output) is already enabled by
  default for Markdown and ePub — you don't need to add `+raw_html` explicitly, but it
  is harmless if you do.
- `--standalone` — automatically set by pandoc for ePub3 output. You do not need to
  include it explicitly, but it is harmless if you do.

### The YAML `---` Gotcha

Pandoc's `yaml_metadata_block` extension treats `---` *anywhere in the document* as a
YAML metadata block delimiter — not just at the top. A horizontal rule (`---`) somewhere
in your content will trigger a cryptic parse error:

```
Error parsing YAML metadata (line 387, column 1):
mapping values are not allowed in this context
```

**Fix:** Disable this extension with `-yaml_metadata_block` in the `--from` flag, and
pass all metadata via `--metadata` flags instead of embedding it as YAML in the source.

## Gotchas and How to Fix Them

### Double-processing of image paths

If your pipeline converts format-specific image syntax into standard Markdown before
rewriting paths, run the conversion **first**, then the path rewriter **once**.

Example: a React MDX source uses `<Image src={heroImg} alt="Hero" />` (where `heroImg` is
imported from `../img/hero.png`). Your first pass converts that to
`![Hero](../img/hero.png)`. If `rewrite_image_paths` already ran before this conversion,
the newly-produced `![Hero](../img/hero.png)` is never processed. If it runs after, it
correctly rewrites the path once. Running it in both places applies the transformation
twice and produces a broken path.

The same applies to any format that uses non-standard image syntax: RST `.. image::`,
AsciiDoc `image::`, custom shortcodes, etc.

**Rule:** convert format-specific syntax to Markdown images **first**, then run
`rewrite_image_paths` **once**.

### Files without H1

Some source files may start with H2 or lower — for example, if a title was part of a UI
component that got stripped during pre-processing. If you combine these without adding a
title, they become subsections of the **previous** chapter — silently wrong, no warning.

Always check: does every file have an H1? If not, prepend one from your TOC/metadata
using `ensure_h1`.

### TeX math in ePub

Pandoc converts `$...$` LaTeX math to MathML for ePub. This works for simple expressions
but fails for complex ones, producing warnings like:

```
[WARNING] Could not convert TeX math \frac{9}{5}C + 32, rendering as TeX
```

The raw TeX appears as-is in the output. Options:

- Accept it for minor expressions (readable enough as-is)
- Use `--webtex` to render math as images via an external service
- Pre-render math to PNG images before building the ePub

### Large image sets

If your book contains many large images, some e-readers slow down or struggle to render
the ePub. Optimise before building:

- Resize to max 1500 px wide (sufficient for any e-reader, including high-DPI e-ink)
- JPEG quality 80 for photos
- PNG with default compression for diagrams
- Target 150 DPI (e-ink screens are typically 200–300 PPI but render at effective lower
  resolution due to the rendering engine)

### Encoding

All source files must be UTF-8. If pandoc produces garbled characters, check for
incorrect encoding or a byte-order mark (BOM) — remove the BOM with your editor or with
`sed -i 's/^\xEF\xBB\xBF//' file.md`.

## Validation

After building, validate with [EPUBCheck](https://www.w3.org/publishing/epubcheck/)
(requires Java):

```bash
java -jar epubcheck.jar book.epub
```

Common validation errors:

- **Duplicate IDs** — two headings that slugify to the same ID (e.g., two sections both
  titled "Overview"). Fix: ensure unique heading text, or assign explicit IDs with
  `## Overview {#overview-intro}`.
- **Missing alt text** on images.
- **Invalid XHTML** — malformed raw HTML in your Markdown source. Use a linter on your
  source HTML before combining.

## Complete Build Script Pattern

This pattern handles the full pipeline: TOC config, heading normalisation, image path
rewriting, and the pandoc call.

### TOC Config Format

Create a JSON file listing all source files in reading order:

```json
[
    {"title": "Introduction",     "file": "intro.md",          "depth": 0},
    {"title": "Getting Started",  "file": "ch1/start.md",      "depth": 1},
    {"title": "Configuration",    "file": "ch1/config.md",     "depth": 1},
    {"title": "Advanced Topics",  "file": "advanced.md",       "depth": 0},
    {"title": "Caching",          "file": "adv/caching.md",    "depth": 1}
]
```

`depth` controls heading shifting: `0` = chapter (H1 stays H1), `1` = subchapter (H1
becomes H2), `2` = sub-subchapter (H1 becomes H3).

Example heading shifts:

| Source heading | depth=0 | depth=1 | depth=2 |
|---|---|---|---|
| H1 | H1 | H2 | H3 |
| H2 | H2 | H3 | H4 |
| H3 | H3 | H4 | H5 |

Note: `--toc-depth=3` includes H1–H3 in the TOC. A file at `depth=2` whose source had H1
and H2 contributes H3 and H4 headings after shifting. Only the H3 appears in the TOC; H4
does not. Increase `--toc-depth` if you need deeper entries to appear in navigation.

For large projects, generate this file programmatically from your existing navigation
structure (e.g., a sidebar config, a `_toc.yml`, or a site's nav JSON) rather than
authoring it by hand.

If a file listed in the TOC does not exist on disk, a synthetic heading is injected to
preserve the chapter hierarchy — useful for section landing pages that were never written.

### The Script

```python
#!/usr/bin/env python3
"""Build an ePub from a directory of Markdown files with a TOC config."""

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path


def load_toc(toc_path: str) -> list[dict]:
    return json.loads(Path(toc_path).read_text(encoding="utf-8"))


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


def build_epub(
    toc_path: str,
    resource_path: str,
    output_path: str,
    css_path: str,
    title: str = "Untitled",
    author: str = "Unknown",
    lang: str = "en",
    cover_image: str | None = None,
    include_copyright: bool = True,
    copyright_year: str = "2025",
) -> None:
    toc_entries = load_toc(toc_path)
    parts: list[str] = []

    if include_copyright:
        # Copyright page — unnumbered so it gets no chapter number
        parts.append(f"# Copyright {{.unnumbered}}\n\n© {copyright_year} {author}\n\n")

    for entry in toc_entries:
        filepath = Path(resource_path) / entry["file"]
        depth = entry.get("depth", 0)
        title_text = entry["title"]

        if not filepath.exists():
            # Synthetic header for sections with no content file
            parts.append(f"# {title_text}\n\n")
            continue

        content = filepath.read_text(encoding="utf-8")
        content = rewrite_image_paths(content, str(filepath.parent), resource_path)
        content = ensure_h1(content, title_text)
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
        f"--output={output_path}",
        f"--metadata=title:{title}",
        f"--metadata=author:{author}",
        f"--metadata=lang:{lang}",
        "--toc", "--toc-depth=3",
        "--split-level=2",
        "--number-sections",
        f"--css={css_path}",
        f"--resource-path={resource_path}",
    ]
    if cover_image:
        cmd.append(f"--epub-cover-image={cover_image}")

    try:
        subprocess.run(cmd, check=True)
    finally:
        os.unlink(tmp_path)


if __name__ == "__main__":
    build_epub(
        toc_path="toc.json",
        resource_path="/path/to/project",
        output_path="book.epub",
        css_path="/path/to/epub-style.css",
        title="My Book",
        author="Author Name",
        cover_image="cover.png",
    )
```

## Quick Reference

| Requirement | How |
|---|---|
| Pandoc version | ≥ 3.0 |
| Title page | `--metadata=title:...` + `--metadata=author:...` |
| Copyright page | First section with `{.unnumbered}` |
| Cover image | `--epub-cover-image=cover.png` |
| Clickable TOC | `--toc --toc-depth=3` |
| Chapter numbering | `--number-sections` |
| Chapter splits | `--split-level=2` |
| Images embedded | `--resource-path=...` (pandoc embeds automatically) |
| Image paths fixed | `rewrite_image_paths()` per source file before combining |
| E-ink stylesheet | `@epub-style.css` via `--css=...` |
| Avoid YAML errors | `--from=markdown-yaml_metadata_block` |
| Footnotes | `[^1]` / `^[inline]` — rendered as ePub pop-ups |
| Internal links | `[text](#heading-id)` — works across split files |
| Validate | `java -jar epubcheck.jar book.epub` |
