# Third-party modules

The files in citation_integrity/ originate from quzhiii/thesis-skills at commit `e15ccc5b5208260b1eb77f1e9dfc1868a54bf9eb`:

- core/citation_integrity/models.py
- core/citation_integrity/bib_parser.py
- core/citation_integrity/tex_parser.py
- core/citation_integrity/cross_reference_lint.py

Source: https://github.com/quzhiii/thesis-skills

Original MIT license and copyright are retained in LICENSE-thesis-skills. Changes: three imports changed from core.citation_integrity.models to package-local .models; comments identify those changes. No upstream installer, networking, model orchestration or write actions are included.

The parsers use regular expressions, not a complete TeX/BibTeX interpreter. The local wrapper reports this limitation and never claims compilation, author-year reference support, arbitrary macro support or semantic citation verification.
