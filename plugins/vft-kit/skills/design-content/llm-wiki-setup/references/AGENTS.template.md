# LLM Wiki Schema

This repository is a persistent LLM-maintained wiki built from raw source material.

## Repository Layers

- `raw/`: immutable source material; read-only unless the user explicitly adds new sources
- `wiki/`: maintained knowledge layer; this is the primary working area
- `output/`: generated deliverables such as reports or slide decks

## Operating Rules

- Do not rewrite or normalize files under `raw/` unless the user explicitly asks.
- Read `wiki/index.md` before broad searches or broad questions.
- Update existing wiki pages before creating near-duplicate new pages.
- Preserve uncertainty, disagreement, and source boundaries.
- After ingest, synthesis, or major maintenance, append an entry to `wiki/log.md`.

## Workflows

### Ingest

1. Read the new source in `raw/`.
2. Find affected pages in `wiki/`.
3. Update or create focused pages.
4. Update `wiki/index.md` if entry points changed.
5. Append an operation note to `wiki/log.md`.

### Query

1. Search `wiki/` first.
2. Answer from maintained pages.
3. Only inspect `raw/` if the wiki is insufficient and the task requires it.

### Generate

1. Build reports or other outputs from `wiki/`.
2. Preserve traceability back to wiki pages.

## Style

- Prefer markdown with clear headings.
- Prefer wikilinks when useful in the local vault.
- Keep pages focused; split pages that become too broad.
