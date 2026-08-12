/**
 * Builds a lookup table mapping Factorio API names (classes, concepts,
 * events, defines, prototypes, types) to their doc page URLs, sourced from
 * the official machine-readable JSON that lua-api.factorio.com publishes.
 *
 * Reference: https://lua-api.factorio.com/latest/auxiliary/json-docs-runtime.html
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const DEFAULT_BASE = 'https://lua-api.factorio.com';

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, {headers: {'User-Agent': 'docusaurus-plugin-factorio-links'}}, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`GET ${url} -> ${res.statusCode}`));
          res.resume();
          return;
        }
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch (err) {
            reject(err);
          }
        });
      })
      .on('error', reject);
  });
}

// Precedence when a bare [[Name]] link matches more than one category.
const CATEGORY_PRECEDENCE = ['classes', 'concepts', 'events', 'defines', 'prototypes', 'types'];

/**
 * Flattens the `defines` tree from runtime-api.json into dotted paths,
 * e.g. { name: 'direction', values: [...], subkeys: [{name:'north', ...}] }
 * -> "direction", "direction.north"
 */
function flattenDefines(defines, prefix, out) {
  for (const def of defines || []) {
    const dotted = prefix ? `${prefix}.${def.name}` : def.name;
    out.push(dotted);
    if (def.values) {
      for (const v of def.values) {
        out.push(`${dotted}.${v.name}`);
      }
    }
    if (def.subkeys) {
      flattenDefines(def.subkeys, dotted, out);
    }
  }
}

async function buildIndex({apiVersion = 'latest', baseUrl = DEFAULT_BASE} = {}) {
  const index = new Map(); // lowercased name -> { name, category, url }

  const add = (name, category, url) => {
    const key = name.toLowerCase();
    const existing = index.get(key);
    if (!existing || CATEGORY_PRECEDENCE.indexOf(category) < CATEGORY_PRECEDENCE.indexOf(existing.category)) {
      index.set(key, {name, category, url});
    }
    // Always keep a category-qualified key too, e.g. "events/on_tick".
    index.set(`${category}/${key}`, {name, category, url});
  };

  const runtime = await fetchJson(`${baseUrl}/${apiVersion}/runtime-api.json`);

  for (const cls of runtime.classes || []) {
    add(cls.name, 'classes', `${baseUrl}/${apiVersion}/classes/${cls.name}.html`);
  }
  for (const concept of runtime.concepts || []) {
    add(concept.name, 'concepts', `${baseUrl}/${apiVersion}/concepts/${concept.name}.html`);
  }
  for (const event of runtime.events || []) {
    add(event.name, 'events', `${baseUrl}/${apiVersion}/events.html#${event.name}`);
  }
  const definePaths = [];
  flattenDefines(runtime.defines, '', definePaths);
  for (const dotted of definePaths) {
    add(dotted, 'defines', `${baseUrl}/${apiVersion}/defines.html#defines.${dotted}`);
  }

  try {
    const prototype = await fetchJson(`${baseUrl}/${apiVersion}/prototype-api.json`);
    for (const proto of prototype.prototypes || []) {
      add(proto.name, 'prototypes', `${baseUrl}/${apiVersion}/prototypes/${proto.name}.html`);
    }
    for (const type of prototype.types || []) {
      add(type.name, 'types', `${baseUrl}/${apiVersion}/types/${type.name}.html`);
    }
  } catch (err) {
    // Prototype docs are a bonus, not a hard requirement — keep going without them.
    console.warn(`[factorio-links] could not load prototype-api.json: ${err.message}`);
  }

  return Object.fromEntries(index);
}

async function loadIndex({apiVersion = 'latest', baseUrl = DEFAULT_BASE, cacheFile, maxAgeMs = 24 * 60 * 60 * 1000} = {}) {
  const cachePath = cacheFile || path.join(__dirname, `.cache.${apiVersion}.json`);

  if (fs.existsSync(cachePath)) {
    const stat = fs.statSync(cachePath);
    if (Date.now() - stat.mtimeMs < maxAgeMs) {
      try {
        return JSON.parse(fs.readFileSync(cachePath, 'utf8'));
      } catch (err) {
        // fall through and rebuild on a corrupt cache
      }
    }
  }

  const index = await buildIndex({apiVersion, baseUrl});
  try {
    fs.mkdirSync(path.dirname(cachePath), {recursive: true});
    fs.writeFileSync(cachePath, JSON.stringify(index), 'utf8');
  } catch (err) {
    console.warn(`[factorio-links] could not write cache to ${cachePath}: ${err.message}`);
  }
  return index;
}

module.exports = {buildIndex, loadIndex};
