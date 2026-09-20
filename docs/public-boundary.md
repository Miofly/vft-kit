# Public boundary

`vft-kit` contains reusable skills only. A public skill may depend on a CLI, an
environment variable, an ignored local config file, or a user-provided project
path. It must not depend on a specific person's home directory, account,
company host, private repository, business database, or credential vault.

When importing a skill from another workspace:

1. Keep the generic workflow and scripts.
2. Replace account and project defaults with explicit input, environment
   variables, or `<example>` placeholders.
3. Remove private examples, live URLs, internal hostnames, and process notes.
4. Add the skill to `catalog/skills.json` and run both checks:

   ```bash
   node scripts/validate-skill-catalog.mjs
   node scripts/audit-public.mjs
   ```

Private wrappers belong in a separate plugin. They may call a public skill, but
the public layer must remain usable without that wrapper or its credentials.
