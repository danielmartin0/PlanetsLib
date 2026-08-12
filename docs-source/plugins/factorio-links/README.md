# Generated in Claude with the following prompt:

"Write a Docusaurus plugin that adds hyperlinks to the Factorio API docs wherever wikipedia style page links are added to docs."

# remark-factorio-links

A remark plugin for Docusaurus that turns wikipedia-style `[[Page]]` links
in your `.md`/`.mdx` docs into hyperlinks to the official Factorio Lua API
docs (`lua-api.factorio.com`).

It works by downloading Factorio's machine-readable `runtime-api.json` and
`prototype-api.json` at build time (cached to disk for 24h by default) and
building a name → doc-page-URL index from it — so it stays correct across
API versions instead of hardcoding URLs.

## Syntax

```md
See [[LuaEntity]] for details.
Rotate with [[defines/direction.north]].
The [[events/on_tick]] event fires every tick.
Custom text: [[LuaEntity|the entity class]].
```

- `[[Name]]` — resolved by name. If the name exists in more than one
  category (classes, concepts, events, defines, prototypes, types), the
  first match wins in that precedence order.
- `[[category/Name]]` — disambiguates explicitly, e.g. `[[events/on_tick]]`
  or `[[defines/direction.north]]` (defines support dotted paths).
- `[[Name|display text]]` — link text differs from the resolved page name.
- Unresolved targets are left as plain text (brackets stripped) and a
  build-time warning is emitted — nothing breaks the build by default.

## Install

```bash
npm install unist-util-visit
```

Copy `api-index.js` and `remark-factorio-links.js` into your site, e.g.
`plugins/factorio-links/`.

## Configure

In `docusaurus.config.js`:

```js
const factorioLinks = require('./plugins/factorio-links/remark-factorio-links');

module.exports = {
  presets: [
    [
      'classic',
      {
        docs: {
          remarkPlugins: [[factorioLinks, {apiVersion: 'latest'}]],
        },
      },
    ],
  ],
};
```

## Options

| Option        | Default      | Description                                                                 |
|---------------|--------------|-------------------------------------------------------------------------------|
| `apiVersion`  | `'latest'`   | Docs version to link against, e.g. `'2.0.28'`.                              |
| `baseUrl`     | lua-api.factorio.com | Override if you mirror the docs.                                    |
| `cacheFile`   | `.cache.<apiVersion>.json` next to `api-index.js` | Where the built index is cached. |
| `maxAgeMs`    | 24h          | How long the cache is considered fresh before re-fetching.                  |
| `onUnresolved`| `'warn'`     | `'warn'` \| `'ignore'` \| `'throw'` — what to do with unresolved `[[links]]`. |

## Notes

- Requires network access during the Docusaurus build (to fetch the JSON
  manifests the first time, or whenever the cache expires). Commit the
  cache file if your CI has no network access.
- Text inside inline code (`` `[[like this]]` ``) and inside existing
  links is left untouched.
- Styling hook: resolved links get `className="factorio-api-link
  factorio-api-<category>"` (e.g. `factorio-api-classes`) so you can style
  them differently per category in your CSS.
