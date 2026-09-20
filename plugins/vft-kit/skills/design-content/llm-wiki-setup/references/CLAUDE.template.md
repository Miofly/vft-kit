# LLM Wiki Schema

This repository is a persistent wiki maintained by an LLM agent.

## Directory Contract

- `raw/` contains source material and is treated as read-only.
- `wiki/` contains maintained knowledge pages and is the main editable layer.
- `output/` contains generated artifacts.

## Rules

- Start broad queries from `wiki/index.md`.
- Prefer updating existing pages over creating duplicates.
- Record meaningful ingest or synthesis operations in `wiki/log.md`.
- Keep claims traceable to either wiki pages or raw sources.
- Preserve disagreements and uncertainty instead of collapsing them too early.

## Recommended Workflow

### Ingest

- Read source from `raw/`
- Update relevant pages in `wiki/`
- Update `wiki/index.md` when the structure changes
- Append to `wiki/log.md`

### Query

- Read `wiki/index.md`
- Search relevant pages in `wiki/`
- Answer from the wiki before consulting raw sources

### Generate

- Produce reports or slides from `wiki/`
- Keep references back to the relevant pages
