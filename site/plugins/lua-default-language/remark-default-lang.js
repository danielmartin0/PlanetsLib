/**
 * remark-default-lang.js
 *
 * A Docusaurus/remark plugin that sets a default syntax-highlighting
 * language on any fenced code block that doesn't already specify one.
 *
 * Example:
 *   ```
 *   local x = 1
 *   ```
 * becomes (at the AST level) equivalent to:
 *   ```lua
 *   local x = 1
 *   ```
 *
 * No external dependencies (no unist-util-visit) so it works regardless
 * of whether your Docusaurus config is CommonJS or ESM.
 */

function remarkDefaultLang(options = {}) {
  const defaultLang = options.lang || 'lua';

  // Manual recursive walk of the mdast tree, looking for `code` nodes.
  function visit(node) {
    if (!node) return;

    if (node.type === 'code' && !node.lang) {
      node.lang = defaultLang;
    }

    if (Array.isArray(node.children)) {
      for (const child of node.children) {
        visit(child);
      }
    }
  }

  return (tree) => {
    visit(tree);
  };
}

module.exports = remarkDefaultLang;
