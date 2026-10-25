#!/usr/bin/env python3
"""fdoc - a fast, read-only CLI for the Factorio prototype/runtime JSON docs.

The Factorio docs live in two large JSON files (prototype-api.json and
runtime-api.json). Answering a single question usually means writing a throwaway
``python3 -c "import json; ..."`` snippet, and following an inheritance chain or a
type reference can take several of them. This tool turns those lookups into one
command with readable, token-friendly output.

Examples
--------
    fdoc info                          # versions, stages, counts
    fdoc list prototypes               # all prototype class names
    fdoc prototype accumulator         # by `typename` (in-game "type")
    fdoc prototype AccumulatorPrototype
    fdoc type Sprite                   # a prototype data type
    fdoc class LuaInventory            # a runtime class, incl. inherited members
    fdoc event on_built_entity
    fdoc concept MapPosition
    fdoc define direction              # a defines.* group
    fdoc define control_behavior       # nested defines.* group
    fdoc get runtime:LuaBootstrap::raise_event
    fdoc get prototype:AccumulatorPrototype
    fdoc get LocalisedString           # "figure out what this name is"
    fdoc member stack_size             # where is this property/attribute used?
    fdoc search "circuit wire"         # free-text search over names/descriptions

Every command accepts ``--json`` to print the raw documentation entry instead of
the formatted view. Add ``--full`` to keep untruncated descriptions and extra
metadata (raises, subclasses, examples).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

DEFAULT_DOCS_DIR = "/opt/factorio_space_age_21/doc-html"

# Populated by main().
DOCS_DIR = DEFAULT_DOCS_DIR
FULL = False

_CACHE: dict[str, dict] = {}


# --------------------------------------------------------------------------- #
# Loading / indexing
# --------------------------------------------------------------------------- #
def load(filename: str) -> dict:
    """Load and cache one of the documentation JSON files."""
    if filename not in _CACHE:
        path = os.path.join(DOCS_DIR, filename)
        with open(path, encoding="utf-8") as fh:
            _CACHE[filename] = json.load(fh)
    return _CACHE[filename]


def prototypes() -> list:
    return load("prototype-api.json")["prototypes"]


def proto_types() -> list:
    return load("prototype-api.json")["types"]


def defines() -> list:
    # Both files carry the same defines tree; prefer the runtime copy.
    return load("runtime-api.json")["defines"]


def classes() -> list:
    return load("runtime-api.json")["classes"]


def events() -> list:
    return load("runtime-api.json")["events"]


def concepts() -> list:
    return load("runtime-api.json")["concepts"]


def globals_() -> list:
    ra = load("runtime-api.json")
    return ra["global_objects"] + ra["global_functions"]


def by_name(items) -> dict:
    return {it["name"]: it for it in items}


# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #
def norm(text: str) -> str:
    """Normalise a name for forgiving, case/punctuation-insensitive matching."""
    return re.sub(r"[^a-z0-9]", "", str(text).lower())


def collapse(text: str) -> str:
    return " ".join(str(text).split())


def yn(value) -> str:
    return "yes" if value else "no"


def fmt_desc(text) -> str:
    """Format a member/description string for inline display."""
    if not text:
        return ""
    text = str(text)
    if FULL:
        return collapse(text)
    text = collapse(text)
    if len(text) > 220:
        text = text[:219].rstrip() + "…"
    return text


def print_description(text, indent: str = "  ") -> None:
    """Print a top-level description, keeping paragraph structure."""
    if not text:
        return
    text = str(text)
    if not FULL and "\n" not in text and len(text) <= 220:
        print(f"{indent}description: {text}")
        return
    lines = text.splitlines()
    if len(lines) == 1:
        print(f"{indent}description: {lines[0]}")
        return
    print(f"{indent}description:")
    first = True
    for line in lines:
        if first:
            print(f"{indent}  {line}")
            first = False
        else:
            print(f"{indent}  {line}" if line.strip() else "")


def print_examples(examples, indent: str = "  ") -> None:
    for i, ex in enumerate(examples, 1):
        print(f"{indent}example {i}:")
        for line in str(ex).splitlines():
            print(f"{indent}  {line}")


def rows_out(rows, indent: int = 4) -> None:
    """Print aligned (name, type, flags, description) rows."""
    if not rows:
        print(" " * indent + "(none)")
        return
    nw = min(max(len(r[0]) for r in rows), 34)
    tw = min(max((len(r[1]) for r in rows), default=0), 46)
    pad = " " * indent
    for name, typ, flags, desc in rows:
        line = pad + name + " " * max(0, nw - len(name))
        if typ:
            line += "  " + typ + " " * max(0, tw - len(typ))
        if flags:
            line += "  [" + flags + "]"
        if desc:
            line += "  -- " + desc
        print(line.rstrip())


# --------------------------------------------------------------------------- #
# Type rendering
# --------------------------------------------------------------------------- #
def render_type(t) -> str:
    """Render a documentation type descriptor as a short readable string."""
    if t is None:
        return "?"
    if isinstance(t, str):
        return t
    if isinstance(t, list):
        return " | ".join(render_type(x) for x in t)
    if not isinstance(t, dict):
        return str(t)

    ct = t.get("complex_type")
    if ct == "literal":
        value = t.get("value")
        return f'"{value}"' if isinstance(value, str) else str(value)
    if ct == "array":
        return render_type(t.get("value")) + "[]"
    if ct == "union":
        return " | ".join(render_type(o) for o in t.get("options", []))
    if ct == "tuple":
        return "(" + ", ".join(render_type(v) for v in t.get("values", [])) + ")"
    if ct == "dictionary":
        return "{" + render_type(t.get("key")) + " -> " + render_type(t.get("value")) + "}"
    if ct == "struct":
        return "struct"
    if ct == "type":
        value = t.get("value")
        desc = t.get("description")
        return f"{value}" + (f" ({collapse(desc)})" if desc else "")
    if ct == "function":
        return "function(" + ", ".join(render_type(p) for p in t.get("parameters", [])) + ")"
    if ct == "table":
        return "table"
    if ct == "LuaCustomTable":
        return "{" + render_type(t.get("key")) + " -> " + render_type(t.get("value")) + "}"
    if ct == "LuaLazyLoadedValue":
        return "LazyValue<" + render_type(t.get("value")) + ">"
    if ct == "LuaStruct":
        return "LuaStruct"
    if ct == "builtin":
        return "builtin"
    return ct or "?"


def render_param(p) -> str:
    name = p.get("name") or f"arg{p.get('order', 0)}"
    text = f"{name}: {render_type(p.get('type'))}"
    if p.get("optional"):
        text += "?"
    return text


def render_callable(name: str, m: dict) -> str:
    """Render a method/operator as ``name(args) -> returns``."""
    fmt = m.get("format") or {}
    params = m.get("parameters")
    if params:
        args = ", ".join(render_param(p) for p in params)
    elif fmt.get("takes_table"):
        args = "table"
    else:
        args = ""
    sig = f"{name}({args})"
    rets = m.get("return_values") or []
    if rets:
        sig += " -> " + ", ".join(render_type(r.get("type")) for r in rets)
    if m.get("variadic_parameter"):
        sig += " ..."
    return sig


def render_attribute_type(a) -> str:
    read = a.get("read_type")
    write = a.get("write_type")
    if read is not None and write is not None:
        rs, ws = render_type(read), render_type(write)
        return rs if rs == ws else f"read {rs} / write {ws}"
    if read is not None:
        return render_type(read)
    if write is not None:
        return f"write {render_type(write)}"
    return "?"


# --------------------------------------------------------------------------- #
# Lookup
# --------------------------------------------------------------------------- #
def lookup(items, query: str, extra_keys=()):
    """Find ``query`` in ``items``. Returns (item | None, candidates)."""
    query = query.strip()
    if not query:
        return None, []
    for it in items:
        if it.get("name") == query or any(it.get(k) == query for k in extra_keys):
            return it, []
    qn = norm(query)
    ci = [
        it
        for it in items
        if norm(it.get("name")) == qn
        or any(norm(it.get(k)) == qn for k in extra_keys)
    ]
    if len(ci) == 1:
        return ci[0], []
    if len(ci) > 1:
        return None, ci
    sub = [
        it
        for it in items
        if qn in norm(it.get("name"))
        or any(qn in norm(it.get(k)) for k in extra_keys)
    ]
    if len(sub) == 1:
        return sub[0], []
    return None, sub


def fail_lookup(query: str, candidates, kind: str) -> int:
    if candidates:
        print(
            f"No exact {kind} match for {query!r}. Did you mean one of:",
            file=sys.stderr,
        )
        for c in candidates[:40]:
            extra = f'  (type "{c["typename"]}")' if c.get("typename") else ""
            print(f"  {c['name']}{extra}", file=sys.stderr)
        if len(candidates) > 40:
            print(f"  ... and {len(candidates) - 40} more", file=sys.stderr)
        return 3
    print(f"No {kind} found matching {query!r}.", file=sys.stderr)
    return 3


def chain_objects(obj, index: dict, *, own_only=False, max_depth=0, parent_key="parent"):
    """Return [obj, parent, grandparent, ...] resolved through ``index``."""
    chain = [obj]
    if own_only:
        return chain
    cur, depth = obj, 0
    while True:
        parent = cur.get(parent_key)
        if not parent:
            break
        nxt = index.get(parent)
        if not nxt:
            chain.append({"_missing_name": parent})
            break
        chain.append(nxt)
        cur = nxt
        depth += 1
        if max_depth and depth >= max_depth:
            break
    return chain


# --------------------------------------------------------------------------- #
# Renderers
# --------------------------------------------------------------------------- #
def render_prototype(p, args) -> None:
    typename = p.get("typename")
    title = p["name"]
    if typename:
        title += f'  (type = "{typename}")'
    print(title)

    meta = []
    if p.get("parent"):
        meta.append(f"parent: {p['parent']}")
    meta.append(f"abstract: {yn(p.get('abstract'))}")
    if p.get("deprecated"):
        meta.append("deprecated: yes")
    if p.get("instance_limit") is not None:
        meta.append(f"instance_limit: {p['instance_limit']}")
    if p.get("visibility"):
        meta.append("visibility: " + ",".join(p["visibility"]))
    print("  " + "   ".join(meta))
    print_description(p.get("description"))

    examples = p.get("examples") or []
    if examples:
        if args.examples:
            print(f"  examples ({len(examples)}):")
            print_examples(examples, "    ")
        else:
            print(f"  examples: {len(examples)} (use --examples to show)")

    if p.get("custom_properties"):
        cp = p["custom_properties"]
        if isinstance(cp, dict) and cp.get("description"):
            print("  custom_properties: " + fmt_desc(cp["description"]))

    chain = chain_objects(
        p, by_name(prototypes()), own_only=args.own_only, max_depth=args.depth
    )
    render_property_chain(chain)


def render_property_chain(chain) -> None:
    total = sum(len(c.get("properties") or []) for c in chain)
    origin = chain[0]["name"]
    if len(chain) > 1:
        print(f"  Properties ({total} incl. inherited):")
    else:
        print(f"  Properties ({total}):")

    for i, owner in enumerate(chain):
        props = owner.get("properties") or []
        if not props:
            continue
        if i == 0:
            label = origin
        elif "_missing_name" in owner:
            print(f"    -- unresolved parent: {owner['_missing_name']} --")
            continue
        else:
            label = f"inherited from {owner['name']}"
        print(f"    -- {label} --")
        rows = []
        for prop in sorted(props, key=lambda x: x.get("order", 0)):
            flags = []
            if prop.get("optional"):
                flags.append("optional")
            else:
                flags.append("required")
            if "default" in prop:
                flags.append("default=" + render_type(prop["default"]))
            if prop.get("override"):
                flags.append("override")
            rows.append(
                (
                    prop["name"],
                    render_type(prop.get("type")),
                    " ".join(flags),
                    fmt_desc(prop.get("description")),
                )
            )
        rows_out(rows)


def render_type_entry(t, args) -> None:
    kind = render_type(t.get("type"))
    title = t["name"]
    if kind:
        title += f"  ({kind})"
    print(title)

    meta = [f"abstract: {yn(t.get('abstract'))}"]
    if t.get("inline"):
        meta.append("inline: yes")
    if t.get("parent"):
        meta.append(f"parent: {t['parent']}")
    print("  " + "   ".join(meta))
    print_description(t.get("description"))

    if t.get("properties"):
        index = by_name(proto_types())
        chain = chain_objects(
            t, index, own_only=args.own_only, max_depth=args.depth
        )
        render_property_chain(chain)

    examples = t.get("examples") or []
    if examples and args.examples:
        print(f"  examples ({len(examples)}):")
        print_examples(examples, "    ")


def render_class(c, args) -> None:
    print(f"{c['name']}  (runtime class)")
    meta = [f"abstract: {yn(c.get('abstract'))}"]
    if c.get("parent"):
        meta.append(f"parent: {c['parent']}")
    print("  " + "   ".join(meta))
    print_description(c.get("description"))

    chain = chain_objects(c, by_name(classes()), own_only=args.own_only, max_depth=args.depth)

    counts = {
        "methods": sum(len(x.get("methods") or []) for x in chain),
        "attributes": sum(len(x.get("attributes") or []) for x in chain),
        "operators": sum(len(x.get("operators") or []) for x in chain),
    }
    inherited = " incl. inherited" if len(chain) > 1 else ""

    for section in ("methods", "operators", "attributes"):
        total = counts[section]
        if not total:
            continue
        print(f"  {section} ({total}{inherited}):")
        for i, owner in enumerate(chain):
            members = owner.get(section) or []
            if not members:
                continue
            if i > 0:
                if "_missing_name" in owner:
                    print(f"    -- unresolved parent: {owner['_missing_name']} --")
                    continue
                print(f"    -- inherited from {owner['name']} --")
            rows = []
            for m in sorted(members, key=lambda x: x.get("order", 0)):
                if section == "attributes":
                    flags = []
                    if m.get("optional"):
                        flags.append("optional")
                    type_text = render_attribute_type(m)
                else:
                    flags = []
                    type_text = render_callable(m["name"], m)
                if FULL:
                    for key, label in (("raises", "raises"), ("subclasses", "returns"), ("lists", "lists")):
                        if m.get(key):
                            extra = m[key]
                            if isinstance(extra, list) and extra and isinstance(extra[0], dict):
                                extra = ", ".join(x.get("name", "?") for x in extra)
                            elif isinstance(extra, list):
                                extra = ", ".join(str(x) for x in extra)
                            flags.append(f"{label}: {fmt_desc(extra)}")
                rows.append(
                    (m["name"], type_text, " ".join(flags), fmt_desc(m.get("description")))
                )
            rows_out(rows)

    examples = c.get("examples") or []
    if examples and args.examples:
        print(f"  examples ({len(examples)}):")
        print_examples(examples, "    ")


def render_event(e, args) -> None:
    print(f"{e['name']}  (event)")
    if e.get("filter"):
        print(f"  filter: {render_type(e['filter'])}")
    print_description(e.get("description"))

    data = e.get("data") or []
    if data:
        print(f"  data ({len(data)}):")
        rows = []
        for d in sorted(data, key=lambda x: x.get("order", 0)):
            flags = ["optional" if d.get("optional") else "required"]
            rows.append(
                (d["name"], render_type(d.get("type")), " ".join(flags), fmt_desc(d.get("description")))
            )
        rows_out(rows)

    examples = e.get("examples") or []
    if examples and args.examples:
        print(f"  examples ({len(examples)}):")
        print_examples(examples, "    ")


def render_global(g, args) -> None:
    if "parameters" in g or "return_values" in g:
        print(render_callable(g["name"], g) + "  (global function)")
    else:
        print(f"{g['name']}  (global object: {render_type(g.get('type'))})")
    print_description(g.get("description"))


def find_define(name: str):
    """Resolve ``group`` or ``group.subkey.subsubkey`` in the defines tree."""
    parts = [p for p in name.split(".") if p]
    if parts and parts[0] in ("defines", "define"):
        parts = parts[1:]
    if not parts:
        return None, []
    root, cands = lookup(defines(), parts[0])
    if root is None:
        return None, cands
    node = root
    for part in parts[1:]:
        nxt = None
        for sub in node.get("subkeys") or ():
            if sub.get("name") == part:
                nxt = sub
                break
        if nxt is None:
            return None, []
        node = nxt
    return node, [root]


def render_define(d, indent: int = 0, label_prefix: str = "defines") -> None:
    pad = "  " * indent
    print(f"{pad}{label_prefix}.{d['name']}")
    if d.get("description"):
        print(f"{pad}  {fmt_desc(d['description'])}")
    values = d.get("values")
    subkeys = d.get("subkeys")
    if values:
        print(f"{pad}  values ({len(values)}):")
        for v in sorted(values, key=lambda x: x.get("order", 0)):
            desc = fmt_desc(v.get("description"))
            line = f"{pad}    {v['name']}"
            if desc:
                line += "  -- " + desc
            print(line.rstrip())
    if subkeys:
        for sub in sorted(subkeys, key=lambda x: x.get("order", 0)):
            render_define(sub, indent + 1, f"{label_prefix}.{d['name']}")


# --------------------------------------------------------------------------- #
# Search / member lookup
# --------------------------------------------------------------------------- #
def searchable_entries():
    """Yield (category, name, description) for every top-level entry."""
    for p in prototypes():
        desc = p.get("description", "")
        if p.get("typename"):
            desc = f'type="{p["typename"]}" ' + desc
        yield "prototype", p["name"], desc
    for t in proto_types():
        yield "type", t["name"], t.get("description", "")
    for c in classes():
        yield "class", c["name"], c.get("description", "")
    for e in events():
        yield "event", e["name"], e.get("description", "")
    for c in concepts():
        yield "concept", c["name"], c.get("description", "")
    for g in globals_():
        yield "global", g["name"], g.get("description", "")
    for d in defines():
        yield "define", d["name"], d.get("description", "")
        for v in d.get("values", []):
            yield "define value", f"defines.{d['name']}.{v['name']}", v.get("description", "")


def cmd_search(args) -> int:
    terms = [t for t in re.split(r"[^a-z0-9]+", args.text.lower()) if t]
    results = []
    for category, name, desc in searchable_entries():
        # Underscores are word separators in the docs, so treat them as spaces
        # and require every query term to appear somewhere in name+description.
        haystack = (name + " " + (desc or "")).lower().replace("_", " ")
        if terms and all(term in haystack for term in terms):
            results.append((category, name, desc))

    if args.json:
        print(json.dumps([{"category": c, "name": n, "description": d} for c, n, d in results], indent=2))
        return 0

    if not results:
        print(f"No matches for {args.text!r}.")
        return 1

    limit = None if args.all else args.limit
    groups: dict[str, list] = {}
    for category, name, desc in results:
        groups.setdefault(category, []).append((name, desc))

    total = len(results)
    shown = 0
    for category in sorted(groups):
        items = groups[category]
        print(f"{category} ({len(items)}):")
        for name, desc in items:
            if limit is not None and shown >= limit:
                break
            d = fmt_desc(desc)
            line = f"  {name}"
            if d:
                line += "  -- " + d
            print(line.rstrip())
            shown += 1
        if limit is not None and shown >= limit:
            print(f"... (showing {shown} of {total}; use --all or --limit N)")
            break
    return 0


def member_entries():
    """Yield (category, container, member-name, type, description, optional)."""
    for p in prototypes():
        for prop in p.get("properties") or []:
            yield (
                "prototype property",
                p["name"],
                prop["name"],
                render_type(prop.get("type")),
                prop.get("description", ""),
                prop.get("optional"),
            )
    for t in proto_types():
        for prop in t.get("properties") or []:
            yield (
                "type property",
                t["name"],
                prop["name"],
                render_type(prop.get("type")),
                prop.get("description", ""),
                prop.get("optional"),
            )
    for c in classes():
        for a in c.get("attributes") or []:
            yield (
                "class attribute",
                c["name"],
                a["name"],
                render_attribute_type(a),
                a.get("description", ""),
                a.get("optional"),
            )
        for m in c.get("methods") or []:
            yield (
                "class method",
                c["name"],
                m["name"],
                render_callable(m["name"], m),
                m.get("description", ""),
                None,
            )
    for e in events():
        for d in e.get("data") or []:
            yield (
                "event field",
                e["name"],
                d["name"],
                render_type(d.get("type")),
                d.get("description", ""),
                d.get("optional"),
            )


def cmd_member(args) -> int:
    target = args.name
    exact = target.lower()
    results = []
    for category, container, name, typ, desc, optional in member_entries():
        if (name.lower() == exact) or (not args.exact and exact in name.lower()):
            results.append((category, container, name, typ, desc, optional))

    if args.json:
        print(
            json.dumps(
                [
                    {
                        "category": c,
                        "container": ct,
                        "name": n,
                        "type": t,
                        "description": d,
                        "optional": o,
                    }
                    for c, ct, n, t, d, o in results
                ],
                indent=2,
            )
        )
        return 0

    if not results:
        print(f"No member named {target!r}.", file=sys.stderr)
        return 1

    plurals = {
        "prototype property": "prototype properties",
        "type property": "type properties",
        "class attribute": "class attributes",
        "class method": "class methods",
        "event field": "event fields",
    }
    limit = None if args.all else args.limit
    by_category: dict[str, list] = {}
    for row in results:
        by_category.setdefault(row[0], []).append(row)

    shown = 0
    for category in sorted(by_category):
        rows = by_category[category]
        print(f"{plurals.get(category, category)} ({len(rows)}):")
        out = []
        for _, container, name, typ, desc, optional in rows:
            if limit is not None and shown >= limit:
                break
            flags = ""
            if optional is True:
                flags = "optional"
            elif optional is False:
                flags = "required"
            out.append((f"{container}.{name}", typ, flags, fmt_desc(desc)))
            shown += 1
        rows_out(out, indent=2)
        if limit is not None and shown >= limit:
            print(f"... (showing {shown} of {len(results)}; use --all or --limit N)")
            break
    return 0


# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #
def cmd_info(args) -> int:
    pa = load("prototype-api.json")
    ra = load("runtime-api.json")
    if args.json:
        print(
            json.dumps(
                {
                    "prototype": {k: pa[k] for k in ("application", "application_version", "api_version", "stage")},
                    "runtime": {k: ra[k] for k in ("application", "application_version", "api_version", "stage")},
                    "counts": {
                        "prototypes": len(pa["prototypes"]),
                        "prototype_types": len(pa["types"]),
                        "classes": len(ra["classes"]),
                        "events": len(ra["events"]),
                        "concepts": len(ra["concepts"]),
                        "global_objects": len(ra["global_objects"]),
                        "global_functions": len(ra["global_functions"]),
                        "defines": len(ra["defines"]),
                    },
                },
                indent=2,
            )
        )
        return 0
    print(f"docs dir: {DOCS_DIR}")
    print(f"Factorio {pa['application_version']}  (api_version {pa['api_version']})")
    print(f"  prototype stage: {len(pa['prototypes'])} prototypes, {len(pa['types'])} types")
    print(f"  runtime stage:   {len(ra['classes'])} classes, {len(ra['events'])} events, "
          f"{len(ra['concepts'])} concepts")
    print(f"  defines:         {len(ra['defines'])} groups")
    return 0


def cmd_list(args) -> int:
    kind = args.kind.lower()
    if kind in ("proto", "prototype", "prototypes"):
        items = [p["name"] for p in prototypes()]
    elif kind in ("type", "types"):
        items = [t["name"] for t in proto_types()]
    elif kind in ("class", "classes"):
        items = [c["name"] for c in classes()]
    elif kind in ("event", "events"):
        items = [e["name"] for e in events()]
    elif kind in ("concept", "concepts"):
        items = [c["name"] for c in concepts()]
    elif kind in ("define", "defines"):
        items = [d["name"] for d in defines()]
    elif kind in ("global", "globals"):
        items = [g["name"] for g in globals_()]
    else:
        print(
            "Unknown category. Use one of: prototypes, types, classes, events, "
            "concepts, defines, globals",
            file=sys.stderr,
        )
        return 2
    if args.json:
        print(json.dumps(items, indent=2))
    else:
        for name in items:
            print(name)
    return 0


def cmd_prototype(args) -> int:
    items = prototypes()
    obj, cands = lookup(items, args.name, extra_keys=("typename",))
    if obj is None:
        return fail_lookup(args.name, cands, "prototype")
    if args.json:
        print(json.dumps(obj, indent=2))
        return 0
    render_prototype(obj, args)
    return 0


def cmd_type(args) -> int:
    items = proto_types()
    obj, cands = lookup(items, args.name)
    if obj is None:
        # Types and runtime concepts share many names; fall back gracefully.
        concept_obj, concept_cands = lookup(concepts(), args.name)
        if concept_obj is not None:
            return _render_concept(concept_obj, args)
        return fail_lookup(args.name, cands, "type")
    if args.json:
        print(json.dumps(obj, indent=2))
        return 0
    render_type_entry(obj, args)
    return 0


def _render_concept(obj, args) -> int:
    if args.json:
        print(json.dumps(obj, indent=2))
        return 0
    render_type_entry(obj, args)
    return 0


def cmd_class(args) -> int:
    items = classes()
    obj, cands = lookup(items, args.name)
    if obj is None:
        return fail_lookup(args.name, cands, "class")
    if args.json:
        print(json.dumps(obj, indent=2))
        return 0
    render_class(obj, args)
    return 0


def cmd_event(args) -> int:
    items = events()
    obj, cands = lookup(items, args.name)
    if obj is None:
        return fail_lookup(args.name, cands, "event")
    if args.json:
        print(json.dumps(obj, indent=2))
        return 0
    render_event(obj, args)
    return 0


def cmd_concept(args) -> int:
    items = concepts()
    obj, cands = lookup(items, args.name)
    if obj is None:
        return fail_lookup(args.name, cands, "concept")
    return _render_concept(obj, args)


def cmd_define(args) -> int:
    obj, cands = find_define(args.name)
    if obj is None:
        return fail_lookup(args.name, cands, "define")
    if args.json:
        print(json.dumps(obj, indent=2))
        return 0
    parts = [p for p in args.name.strip().split(".") if p]
    if parts and parts[0] in ("defines", "define"):
        parts = parts[1:]
    prefix = "defines" + ("".join("." + p for p in parts[:-1]) if len(parts) > 1 else "")
    render_define(obj, label_prefix=prefix)
    return 0


def cmd_get(args) -> int:
    """Resolve a reference like ``runtime:Class::member`` to the right view."""
    ref = args.ref.strip()
    if args.json:
        return _get_json(ref)

    if ref.startswith("prototype:"):
        name = ref[len("prototype:"):]
        return cmd_prototype(_clone(args, name=name))
    if ref.startswith("runtime:") or ref.startswith("class:"):
        rest = ref.split(":", 1)[1]
        if "::" in rest:
            cls_name, member = rest.split("::", 1)
            cls = by_name(classes()).get(cls_name)
            if not cls:
                return fail_lookup(cls_name, [], "class")
            for section in ("methods", "attributes", "operators"):
                for m in cls.get(section) or []:
                    if m["name"] == member:
                        print(f"{cls_name}::{member}  ({section.rstrip('s')})")
                        print_description(m.get("description"))
                        if section == "attributes":
                            print(f"  type: {render_attribute_type(m)}")
                        else:
                            print(f"  {render_callable(member, m)}")
                        return 0
            print(f"{cls_name} has no member {member!r}.", file=sys.stderr)
            return 3
        return cmd_class(_clone(args, name=rest))
    if ref.startswith("defines.") or ref.startswith("define."):
        return cmd_define(_clone(args, name=ref))
    if ref.startswith("event:"):
        return cmd_event(_clone(args, name=ref[len("event:"):]))
    if ref.startswith("concept:"):
        return cmd_concept(_clone(args, name=ref[len("concept:"):]))
    if ref.startswith("type:"):
        return cmd_type(_clone(args, name=ref[len("type:"):]))

    # Bare name: try each category in turn, most specific first.
    for probe in (
        (prototypes(), ("typename",), "prototype"),
        (proto_types(), (), "type"),
        (classes(), (), "class"),
        (events(), (), "event"),
        (concepts(), (), "concept"),
        (globals_(), (), "global"),
        (defines(), (), "define"),
    ):
        items, keys, kind = probe
        obj, _ = lookup(items, ref, extra_keys=keys)
        if obj is not None:
            if kind == "prototype":
                return cmd_prototype(_clone(args, name=ref))
            if kind == "type":
                return cmd_type(_clone(args, name=ref))
            if kind == "class":
                return cmd_class(_clone(args, name=ref))
            if kind == "event":
                return cmd_event(_clone(args, name=ref))
            if kind == "concept":
                return cmd_concept(_clone(args, name=ref))
            if kind == "global":
                render_global(obj, args)
                return 0
            return cmd_define(_clone(args, name=ref))

    # Resolve a bare ``defines.group`` reference.
    if ref.startswith("defines"):
        return cmd_define(_clone(args, name=ref))
    print(f"Could not resolve {ref!r}.", file=sys.stderr)
    return 3


def _get_json(ref: str) -> int:
    """Best-effort raw JSON lookup for ``get --json``."""
    if "::" in ref:
        cls_name, member = ref.split("::", 1)
        cls_name = cls_name.split(":")[-1]
        cls = by_name(classes()).get(cls_name)
        if cls:
            for section in ("methods", "attributes", "operators"):
                for m in cls.get(section) or []:
                    if m["name"] == member:
                        print(json.dumps(m, indent=2))
                        return 0
    name = ref.split(":", 1)[-1] if ":" in ref else ref
    for items, keys in (
        (prototypes(), ("typename",)),
        (proto_types(), ()),
        (classes(), ()),
        (events(), ()),
        (concepts(), ()),
        (globals_(), ()),
        (defines(), ()),
    ):
        obj, _ = lookup(items, name, extra_keys=keys)
        if obj is not None:
            print(json.dumps(obj, indent=2))
            return 0
    print(json.dumps(None))
    return 3


def _clone(args, **overrides):
    """Copy a namespace, overriding fields (so cmd_* helpers stay reusable)."""
    data = vars(args).copy()
    data.update(overrides)
    return argparse.Namespace(**data)


# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fdoc",
        description="Fast, read-only lookups in the Factorio prototype/runtime JSON docs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--docs-dir",
        default=os.environ.get("FACTORIO_DOCS_DIR", DEFAULT_DOCS_DIR),
        help="directory holding prototype-api.json and runtime-api.json "
        "(default: %(default)s; also FACTORIO_DOCS_DIR)",
    )
    parser.add_argument(
        "--json", action="store_true", help="print the raw documentation entry as JSON"
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="do not truncate descriptions; include extra metadata",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    def add_lookup_parser(name, help_text, aliases=()):
        p = sub.add_parser(name, aliases=list(aliases), help=help_text)
        p.add_argument("name")
        p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
        p.add_argument("--full", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
        p.add_argument("--own-only", action="store_true", help="hide inherited members")
        p.add_argument("--depth", type=int, default=0, help="limit inheritance depth")
        p.add_argument("--examples", action="store_true", help="show examples")
        return p

    p = add_lookup_parser("prototype", "show a prototype class (by name or in-game type)", ("proto", "p"))
    p.set_defaults(func=cmd_prototype)

    p = add_lookup_parser("type", "show a prototype data type", ("t",))
    p.set_defaults(func=cmd_type)

    p = add_lookup_parser("class", "show a runtime class", ("c",))
    p.set_defaults(func=cmd_class)

    p = add_lookup_parser("event", "show a runtime event", ("e",))
    p.set_defaults(func=cmd_event)

    p = add_lookup_parser("concept", "show a runtime concept", ())
    p.set_defaults(func=cmd_concept)

    p = sub.add_parser("define", help="show a defines.* group (nested groups supported)")
    p.add_argument("name")
    p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_define)

    p = sub.add_parser("get", help="resolve a reference such as runtime:Class::method")
    p.add_argument("ref")
    p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.add_argument("--full", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.add_argument("--own-only", action="store_true")
    p.add_argument("--depth", type=int, default=0)
    p.add_argument("--examples", action="store_true")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("search", help="search names and descriptions")
    p.add_argument("text")
    p.add_argument("--limit", type=int, default=25)
    p.add_argument("--all", action="store_true", help="show every match")
    p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("member", help="find where a property/attribute/method/field is defined")
    p.add_argument("name")
    p.add_argument("--limit", type=int, default=25)
    p.add_argument("--all", action="store_true", help="show every match")
    p.add_argument("--exact", action="store_true", help="require an exact name match")
    p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_member)

    p = sub.add_parser("list", help="list all names in a category")
    p.add_argument(
        "kind",
        help="prototypes | types | classes | events | concepts | defines | globals",
    )
    p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("info", help="print versions, stages and entry counts")
    p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)
    p.set_defaults(func=cmd_info)

    return parser


def main(argv=None) -> int:
    global DOCS_DIR, FULL
    parser = build_parser()
    args = parser.parse_args(argv)
    DOCS_DIR = getattr(args, "docs_dir", DEFAULT_DOCS_DIR) or DEFAULT_DOCS_DIR
    FULL = bool(getattr(args, "full", False))

    if not os.path.isfile(os.path.join(DOCS_DIR, "prototype-api.json")):
        print(
            f"Documentation not found in {DOCS_DIR!r}. "
            "Pass --docs-dir or set FACTORIO_DOCS_DIR.",
            file=sys.stderr,
        )
        return 2

    try:
        return args.func(args)
    except BrokenPipeError:
        # Allow piping into `head` without a traceback.
        try:
            sys.stdout.close()
        except Exception:
            pass
        return 0


if __name__ == "__main__":
    sys.exit(main())
