/**
 * remark-factorio-links
 *
 * A remark plugin (used as a Docusaurus docs plugin via `remarkPlugins`)
 * that turns wikipedia-style [[Page]] links into hyperlinks pointing at
 * the official Factorio Lua API docs (https://lua-api.factorio.com).
 *
 * Syntax supported in .md/.mdx:
 *   [[LuaEntity]]                    -> resolved by name, best category wins
 *   [[LuaEntity|the entity]]         -> custom display text
 *   [[events/on_tick]]               -> disambiguate with an explicit category
 *   [[defines/direction.north]]      -> dotted defines paths work too
 *
 * Usage in docusaurus.config.js:
 *   const factorioLinks = require('./plugins/remark-factorio-links');
 *   ...
 *   presets: [
 *     ['classic', {
 *       docs: {
 *         remarkPlugins: [[factorioLinks, { apiVersion: 'latest' }]],
 *       },
 *     }],
 *   ],
 */

const {visit, SKIP} = require('unist-util-visit');
const {loadIndex} = require('./api-index');

// Matches [[Target]] or [[Target|Display Text]]. Target may contain a
// "category/" prefix (e.g. "events/on_tick") and dots (defines paths).
const WIKILINK_RE = /\[\[([a-zA-Z0-9_./-]+)(?:\|([^\]]+))\]\]|\[\[([a-zA-Z0-9_./-]+)\]\]/g;

function resolve(index, target) {
  const key = target.toLowerCase();
  return index[key] || null;
}

function splitTextNode(node, index) {
  const value = node.value;
  const parts = [];
  let lastEnd = 0;
  let match;

  WIKILINK_RE.lastIndex = 0;
  while ((match = WIKILINK_RE.exec(value)) !== null) {
    const [full, targetWithDisplay, display, targetOnly] = match;
    const target = targetWithDisplay || targetOnly;
    const start = match.index;

    if (start > lastEnd) {
      parts.push({type: 'text', value: value.slice(lastEnd, start)});
    }

    const resolved = resolve(index, target);
    if (resolved) {
      parts.push({
        type: 'link',
        url: resolved.url,
        title: `${resolved.category}: ${resolved.name}`,
        children: [{type: 'inlineCode', value: display || resolved.name}],
        data: {hProperties: {className: ['factorio-api-link', `factorio-api-${resolved.category}`]}},
      });
    } else {
      // Unresolved: leave the visible text, drop the brackets, no link.
      parts.push({type: 'text', value: display || target});
    }

    lastEnd = start + full.length;
  }

  if (parts.length === 0) {
    return null; // no wikilinks in this text node
  }

  if (lastEnd < value.length) {
    parts.push({type: 'text', value: value.slice(lastEnd)});
  }

  return parts;
}

function attachWarnings(index, unresolved, file) {
  if (unresolved.size === 0 || !file) return;
  for (const target of unresolved) {
    file.message(`[factorio-links] could not resolve [[${target}]] to a known API page`, undefined, 'remark-factorio-links:unresolved');
  }
}

function remarkFactorioLinks(options = {}) {
  const {apiVersion = 'latest', baseUrl, cacheFile, maxAgeMs, onUnresolved = 'warn'} = options;

  let indexPromise = null;
  const getIndex = () => {
    if (!indexPromise) {
      indexPromise = loadIndex({apiVersion, baseUrl, cacheFile, maxAgeMs});
    }
    return indexPromise;
  };

  return async function transformer(tree, file) {
    const index = await getIndex();
    const unresolved = new Set();

    visit(tree, 'text', (node, idx, parent) => {
      if (!parent || idx === null) return;
      // Skip text that lives inside a link/code node already.
      if (parent.type === 'link' || parent.type === 'inlineCode') return;

      WIKILINK_RE.lastIndex = 0;
      const matches = node.value.match(WIKILINK_RE);
      if (!matches) return;

      for (const m of matches) {
        const targetMatch = /\[\[([a-zA-Z0-9_./-]+)/.exec(m);
        const target = targetMatch && targetMatch[1];
        if (target && !resolve(index, target)) unresolved.add(target);
      }

      const replacement = splitTextNode(node, index);
      if (!replacement) return;

      parent.children.splice(idx, 1, ...replacement);
      return [SKIP, idx + replacement.length];
    });

    if (onUnresolved === 'warn') {
      attachWarnings(index, unresolved, file);
    } else if (onUnresolved === 'throw' && unresolved.size > 0) {
      throw new Error(`[factorio-links] unresolved links: ${[...unresolved].join(', ')}`);
    }
  };
}

module.exports = remarkFactorioLinks;
