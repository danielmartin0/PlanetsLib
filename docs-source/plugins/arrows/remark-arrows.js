/**
 * remark-arrows.js
 *
 * A Docusaurus/remark plugin that replaces plain-text arrow sequences
 * with their Unicode arrow symbols in Markdown content:
 *   ->   becomes  →
 *   <-   becomes  ←
 *   <->  becomes  ↔  (bonus: bidirectional arrow)
 *
 * It only touches "text" AST nodes, so code blocks and inline code
 * (`node.type === 'code' | 'inlineCode'`) are left untouched automatically —
 * no need to special-case them.
 *
 * No external dependencies (like unist-util-visit) are required, which
 * sidesteps ESM/CJS interop issues in Docusaurus configs.
 */

const REPLACEMENTS = [
  // Order matters: handle the longer/combined pattern first so "<->"
  // isn't partially matched by the single-arrow rules below.
  { pattern: /<->/g, replacement: '\u2194' }, // ↔
  { pattern: /->/g, replacement: '\u2192' },  // →
  { pattern: /<-/g, replacement: '\u2190' },  // ←
];

function transformValue(value) {
  let result = value;
  for (const { pattern, replacement } of REPLACEMENTS) {
    result = result.replace(pattern, replacement);
  }
  return result;
}

function visit(node) {
  if (node.type === 'text' && typeof node.value === 'string') {
    node.value = transformValue(node.value);
  }
  if (Array.isArray(node.children)) {
    node.children.forEach(visit);
  }
}

/** @type {import('unified').Plugin} */
function remarkArrows() {
  return (tree) => {
    visit(tree);
  };
}

module.exports = remarkArrows;
