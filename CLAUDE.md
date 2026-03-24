# claude-toolkit

@README.md

## Conventions

- Each plugin is self-contained under `plugins/<plugin-name>/`
- Agents, skills, commands, and hooks are auto-discovered from their respective directories — no explicit path overrides in plugin.json unless using non-standard locations
- Every plugin MUST have a README.md

## Plugin Checklist

New plugins must include:

1. `.claude-plugin/plugin.json` with name, version, description, author, license
2. `README.md` describing the plugin and listing its components
3. At least one component directory (agents/, skills/, commands/, or hooks/)
4. Entry in top-level `.claude-plugin/marketplace.json`
5. Entry in top-level `README.md` plugins table
