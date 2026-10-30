// EVERY PAGE KEEPS ITS OWN WAY OUT (the freeze of the panel's first slot, 25.10.2026): React keeps one instance for an element of the
// same type at the same place, so a component that draws one page and then another of the same kind in its place hands the first
// page's state -- its way out, «leaving» -- to the second: the page is born on its way out, inert, and nothing closes it while the
// app under it stays inert. This check reads every component of src/*.jsx and fails when two or more pages can stand at one place of
// what a component returns -- across its returns, the branches of a ternary and of && || ??, the children of a fragment, what a helper
// of the component returns where it is called -- without a key of their own. A page is <Page> with children (a self-closing
// <Page … /> is a loading frame of the same page and does not count), or an element of a component whose own root is a page. A
// stack -- the page under kept, the page over it keyed (iOS NavigationStack) -- passes.
// usage: node tools/pagekeys.mjs [srcDir]      (no dependencies; exit 0 clean, 1 pages without their keys, 2 a file it cannot read)
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PUNCT = [">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||",
  "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>"];
/** After these words an expression begins: a / there is a regular expression, a < an element. */
const OPENS = new Set(["return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield",
  "await", "export", "default"]);
/** A line that begins with one of these goes on with the expression above it. */
const GOES_ON = new Set(["?", ":", ".", "?.", "&&", "||", "??", "+", "-", "*", "/", "%", "**", "=", "==", "===", "!=", "!==", "<", ">",
  "<=", ">=", "(", "[", "|", "&", "^", "instanceof", "in"]);
const CONTROL = new Set(["if", "for", "while", "switch", "catch", "with"]);

class Unread extends Error {}

/** One file read into tokens; an element is read whole into one token, its expressions into their own tokens. */
function read(s, file) {
  const starts = [0];
  for (let i = 0; i < s.length; i++) if (s[i] === "\n") starts.push(i + 1);
  const lineOf = (i) => { let lo = 0, hi = starts.length - 1; while (lo < hi) { const m = (lo + hi + 1) >> 1; if (starts[m] <= i) lo = m; else hi = m - 1; } return lo + 1; };
  const fail = (i, why) => new Unread(`${file}:${lineOf(i)}: ${why}`);
  const idStart = (c) => /[A-Za-z_$]/.test(c || "");
  const idPart = (c) => /[\w$]/.test(c || "");
  const space = (i) => {
    for (;;) {
      while (i < s.length && /\s/.test(s[i])) i++;
      if (s.startsWith("//", i)) { while (i < s.length && s[i] !== "\n") i++; continue; }
      if (s.startsWith("/*", i)) { const e = s.indexOf("*/", i + 2); i = e < 0 ? s.length : e + 2; continue; }
      return i;
    }
  };
  const quoted = (i) => {
    const q = s[i];
    for (i++; i < s.length; i++) {
      if (s[i] === "\\") { i++; continue; }
      if (s[i] === q) return i + 1;
      if (s[i] === "\n") break;
    }
    throw fail(i, "a string never closes on its line");
  };
  const template = (i) => {
    for (i++; i < s.length; i++) {
      if (s[i] === "\\") { i++; continue; }
      if (s[i] === "`") return i + 1;
      if (s[i] === "$" && s[i + 1] === "{") i = tokens(i + 2, "}").end - 1;
    }
    throw fail(i, "a template never closes");
  };
  const regex = (i) => {
    let cls = false;
    for (i++; i < s.length; i++) {
      const c = s[i];
      if (c === "\\") { i++; continue; }
      if (c === "\n") break;
      if (cls) { if (c === "]") cls = false; }
      else if (c === "[") cls = true;
      else if (c === "/") { i++; while (idPart(s[i])) i++; return i; }
    }
    throw fail(i, "a regular expression never closes on its line");
  };
  const opens = (last) => !last || (last.t === "p" && last.v !== ")" && last.v !== "]") || (last.t === "id" && OPENS.has(last.v));
  // the tokens from i up to the `stop` that closes them (none: the file's end)
  function tokens(i, stop) {
    const list = [];
    let depth = 0, last = null;
    for (;;) {
      i = space(i);
      if (i >= s.length) { if (stop) throw fail(i, `no ${stop} closes this`); return { list, end: i }; }
      const c = s[i], at = i;
      if (stop && depth === 0 && c === stop) return { list, end: i + 1 };
      let tok;
      if (c === "'" || c === "\"") { i = quoted(i); tok = { t: "str" }; }
      else if (c === "`") { i = template(i); tok = { t: "tpl" }; }
      else if (idStart(c)) { let j = i + 1; while (idPart(s[j])) j++; tok = { t: "id", v: s.slice(i, j) }; i = j; }
      else if (/\d/.test(c) || (c === "." && /\d/.test(s[i + 1] || ""))) { let j = i + 1; while (/[\w.]/.test(s[j] || "")) j++; tok = { t: "num" }; i = j; }
      else if (c === "/" && opens(last)) { i = regex(i); tok = { t: "re" }; }
      else if (c === "<" && opens(last) && /[A-Za-z_$>]/.test(s[i + 1] || "")) { const node = element(i); i = node.e; tok = { t: "jsx", node }; }
      else {
        const v = PUNCT.find((p) => s.startsWith(p, i)) || c;
        i += v.length;
        tok = { t: "p", v };
        if (v === "(" || v === "[" || v === "{") depth++;
        else if (v === ")" || v === "]" || v === "}") { if (--depth < 0) throw fail(at, `a ${v} that closes nothing`); }
      }
      tok.s = at; tok.line = lineOf(at);
      list.push(tok);
      last = tok;
    }
  }
  const tagName = (i) => { let j = i; while (/[\w$:.-]/.test(s[j] || "")) j++; return s.slice(i, j); };
  // an element from its < to past its end: the tag, the key, whether it closes itself, its children
  function element(i) {
    const at = i;
    i = space(i + 1);
    const node = { tag: "", key: null, self: false, kids: [], s: at, line: lineOf(at), file };
    if (s[i] === ">") { const k = kids(i + 1, ""); node.kids = k.list; node.e = k.end; return node; }
    node.tag = tagName(i);
    i += node.tag.length;
    for (;;) {
      i = space(i);
      if (s[i] === "/" && s[i + 1] === ">") { node.self = true; node.e = i + 2; return node; }
      if (s[i] === ">") { const k = kids(i + 1, node.tag); node.kids = k.list; node.e = k.end; return node; }
      if (s[i] === "{") { i = tokens(i + 1, "}").end; continue; }   // {...spread}
      const name = tagName(i);
      if (!name) throw fail(i, `an attribute of <${node.tag}> without a name`);
      i = space(i + name.length);
      if (s[i] !== "=") continue;
      i = space(i + 1);
      let key;
      if (s[i] === "\"" || s[i] === "'") { const e = s.indexOf(s[i], i + 1); if (e < 0) throw fail(i, "an attribute's string never closes"); key = s.slice(i, e + 1); i = e + 1; }
      else if (s[i] === "{") { const x = tokens(i + 1, "}"); key = `{${s.slice(i + 1, x.end - 1).trim()}}`; i = x.end; }
      else if (s[i] === "<") { i = element(i).e; }
      else throw fail(i, `the value of ${name} is neither a string, an expression nor an element`);
      if (name === "key") node.key = key;
    }
  }
  // the children up to the tag that closes `tag` ("" a fragment's): elements, expressions and text
  function kids(i, tag) {
    const list = [];
    for (;;) {
      if (i >= s.length) throw fail(i, `<${tag}> never closes`);
      if (s[i] === "<" && s[i + 1] === "/") {
        const j = space(i + 2), name = tagName(j), k = space(j + name.length);
        if (name !== tag || s[k] !== ">") throw fail(i, `</${name}> where </${tag}> closes`);
        return { list, end: k + 1 };
      }
      if (s[i] === "<") { const node = element(i); list.push({ t: "el", node }); i = node.e; continue; }
      if (s[i] === "{") {
        const x = tokens(i + 1, "}");
        if (x.list.length) list.push({ t: "expr", list: x.list });   // {/* a word */} is no child
        i = x.end;
        continue;
      }
      let j = i;
      while (j < s.length && s[j] !== "<" && s[j] !== "{") j++;
      const text = s.slice(i, j);
      if (!(/^\s*$/.test(text) && text.includes("\n"))) list.push({ t: "text" });   // whitespace with a line break is dropped
      i = j;
    }
  }
  return tokens(0, null).list;
}

/** For every bracket of a token list, the index of the one that answers it. */
function pairs(list) {
  const match = new Array(list.length).fill(-1), open = [];
  list.forEach((k, i) => {
    if (k.t !== "p") return;
    if (k.v === "(" || k.v === "[" || k.v === "{") open.push(i);
    else if (k.v === ")" || k.v === "]" || k.v === "}") { const o = open.pop(); match[o] = i; match[i] = o; }
  });
  return match;
}
const endsValue = (k) => ["str", "tpl", "re", "jsx", "num"].includes(k.t) || (k.t === "id" && !OPENS.has(k.v)) || (k.t === "p" && [")", "]", "}"].includes(k.v));
/** Where an expression that begins at a ends: its ; or , , the bracket that closes around it, or a new line it does not go on to. */
function exprEnd(list, match, a) {
  let i = a;
  while (i < list.length) {
    const k = list[i];
    if (k.t === "p" && [";", ",", ")", "]", "}"].includes(k.v)) return i;
    if (i > a && k.line > list[i - 1].line && endsValue(list[i - 1]) && !GOES_ON.has(k.v)) return i;
    if (k.t === "p" && (k.v === "(" || k.v === "[" || k.v === "{")) { i = match[i] + 1; continue; }
    i++;
  }
  return i;
}
/** An arrow function from j: its body, a block or an expression. */
function arrowAt(list, match, j) {
  if (list[j]?.t === "id" && list[j].v === "async") j++;
  let k;
  if (list[j]?.t === "p" && list[j].v === "(") k = match[j] + 1;
  else if (list[j]?.t === "id") k = j + 1;
  else return null;
  if (!(list[k]?.t === "p" && list[k].v === "=>")) return null;
  const b = k + 1;
  if (list[b]?.t === "p" && list[b].v === "{") return { kind: "block", a: b + 1, b: match[b], end: match[b] + 1 };
  const e = exprEnd(list, match, b);
  return { kind: "expr", a: b, b: e, end: e };
}
/** Whether the { at i opens a function's body: after => or after the ) of a function, not of an if, a for, a while, a switch. */
function opensFunction(list, match, i) {
  const p = list[i - 1];
  if (!p || p.t !== "p") return false;
  if (p.v === "=>") return true;
  if (p.v !== ")") return false;
  const q = list[match[i - 1] - 1];
  return !(q && q.t === "id" && CONTROL.has(q.v));
}
/** A function declared at i (`function name(…) {…}` or `const name = (…) => …`): its name, its body and where it ends. */
function declaredAt(list, match, i) {
  const k = list[i];
  if (k.t === "id" && k.v === "function" && list[i + 1]?.t === "id" && list[i + 2]?.v === "(") {
    const body = match[i + 2] + 1;
    if (list[body]?.v !== "{") return null;
    return { name: list[i + 1].v, line: list[i + 1].line, kind: "block", a: body + 1, b: match[body], end: match[body] + 1 };
  }
  if (k.t === "id" && (k.v === "const" || k.v === "let") && list[i + 1]?.t === "id" && list[i + 2]?.v === "=") {
    const fn = arrowAt(list, match, i + 3);
    return fn && { name: list[i + 1].v, line: list[i + 1].line, ...fn };
  }
  return null;
}
/** The returns of a function's own body, not of the functions inside it; and the helpers declared right in it. */
function body(list, match, fn) {
  if (fn.kind === "expr") return { returns: [{ a: fn.a, b: fn.b }], helpers: new Map() };
  const returns = [], helpers = new Map(), braces = [];
  for (let i = fn.a; i < fn.b; i++) {
    const k = list[i];
    if (braces.length === 0) {
      const h = declaredAt(list, match, i);
      if (h) { helpers.set(h.name, { list, match, ...body(list, match, h) }); i = h.end - 1; continue; }
    }
    if (k.t === "p" && k.v === "{") braces.push(opensFunction(list, match, i));
    else if (k.t === "p" && k.v === "}") braces.pop();
    else if (k.t === "id" && k.v === "return" && !braces.includes(true)) returns.push({ a: i + 1, b: exprEnd(list, match, i + 1) });
  }
  return { returns, helpers };
}

/** The elements an expression may draw at its place: both branches of a ternary, every side of && || ??, what a helper returns. */
function shapes(list, match, a, b, helpers, seen = new Set()) {
  if (a >= b) return [];
  if (list[a].t === "p" && list[a].v === "(" && match[a] === b - 1) return shapes(list, match, a + 1, b - 1, helpers, seen);
  const top = [];
  for (let i = a; i < b; i++) {
    const k = list[i];
    if (k.t === "p" && (k.v === "(" || k.v === "[" || k.v === "{")) { i = match[i]; continue; }
    if (k.t === "p") top.push(i);
  }
  const q = top.find((i) => list[i].v === "?");
  if (q != null) {
    let n = 0, colon = -1;
    for (const i of top) {
      if (i <= q) continue;
      if (list[i].v === "?") n++;
      else if (list[i].v === ":") { if (n === 0) { colon = i; break; } n--; }
    }
    return colon < 0 ? [] : [...shapes(list, match, q + 1, colon, helpers, seen), ...shapes(list, match, colon + 1, b, helpers, seen)];
  }
  const ops = top.filter((i) => ["&&", "||", "??"].includes(list[i].v));
  if (ops.length) {
    const cuts = [a - 1, ...ops, b];
    return cuts.slice(1).flatMap((c, j) => shapes(list, match, cuts[j] + 1, c, helpers, seen));
  }
  if (b - a === 1 && list[a].t === "jsx") return [list[a].node];
  const name = list[a].t === "id" ? list[a].v : null;
  if (name && helpers.has(name) && !seen.has(name) && list[a + 1]?.v === "(" && match[a + 1] === b - 1) {
    const h = helpers.get(name), deeper = new Set(seen).add(name);
    return h.returns.flatMap((r) => shapes(h.list, h.match, r.a, r.b, new Map([...helpers, ...h.helpers]), deeper));
  }
  return [];
}

/** What a component returns, place by place: its root elements (an unkeyed fragment at the root is its children, as React reads it). */
function roots(c) {
  const out = [];
  for (const r of c.returns) {
    for (const n of shapes(c.list, c.match, r.a, r.b, c.helpers)) {
      if (n.tag === "" && n.key == null) n.kids.forEach((k, i) => childShapes(k, c.helpers).forEach((m) => out.push([m, "", i])));
      else out.push([n, "", 0]);
    }
  }
  return out;
}
function childShapes(k, helpers) {
  if (k.t === "el") return [k.node];
  if (k.t !== "expr") return [];
  k.match ??= pairs(k.list);
  return shapes(k.list, k.match, 0, k.list.length, helpers);
}
const slotOf = (node, parent, index) => `${parent}/${node.key != null ? `key=${node.key}` : `#${index}`}`;

/** Every page at its place: a map of place and kind to the elements that may stand there. */
function places(c, pageKinds) {
  const found = new Map();
  const visit = (node, parent, index) => {
    const slot = slotOf(node, parent, index);
    if (node.tag === "Page" ? !node.self : pageKinds.has(node.tag)) {
      const at = `${slot} <${node.tag}>`;
      if (!found.has(at)) found.set(at, new Map());
      found.get(at).set(node.s, node);
    }
    node.kids.forEach((k, i) => childShapes(k, c.helpers).forEach((m) => visit(m, `${slot}<${node.tag}>`, i)));
  };
  for (const [n, parent, i] of roots(c)) visit(n, parent, i);
  return found;
}

/** The components of the sources: every top-level function whose name begins with a capital. */
function componentsOf(sources) {
  const all = [];
  for (const [file, text] of sources) {
    const list = read(text, file), match = pairs(list);
    for (let i = 0; i < list.length; i++) {
      const d = declaredAt(list, match, i);
      if (d) {
        if (/^[A-Z]/.test(d.name)) all.push({ file, name: d.name, line: d.line, list, match, ...body(list, match, d) });
        i = d.end - 1;
        continue;
      }
      const k = list[i];
      if (k.t === "p" && (k.v === "(" || k.v === "[" || k.v === "{")) i = match[i];
    }
  }
  return all;
}
/** The components that are pages: their own root is a <Page> or another such component. */
function pageKindsOf(all) {
  const kinds = new Set();
  for (let grew = true; grew;) {
    grew = false;
    for (const c of all) {
      if (kinds.has(c.name)) continue;
      if (roots(c).some(([n]) => n.tag === "Page" || kinds.has(n.tag))) { kinds.add(c.name); grew = true; }
    }
  }
  return kinds;
}
function check(sources) {
  const all = componentsOf(sources), kinds = pageKindsOf(all), faults = [];
  let pages = 0;
  for (const c of all) {
    for (const [at, nodes] of places(c, kinds)) {
      pages += nodes.size;
      if (nodes.size > 1) faults.push({ c, at, nodes: [...nodes.values()] });
    }
  }
  return { all, kinds, faults, pages };
}

// THE CHECK READS ITSELF FIRST: what must fail fails, what must pass passes -- a reader that went blind would pass everything
const PAGE = "export function Page({ children }) { return <div>{children}</div>; }\n";
const FIXTURES = [
  ["two returns", true, "function A({ x }) { if (x) return <Page title=\"a\">a</Page>; return <Page title=\"b\">b</Page>; }"],
  ["a ternary", true, "function A({ x }) { return x ? <Page>a</Page> : <Page>b</Page>; }"],
  ["a fragment's child", true, "function A({ x }) { return (<>\n<Page key=\"r\">r</Page>\n{x ? <Page>a</Page> : <Page>b</Page>}\n</>); }"],
  ["an arrow component", true, "const A = ({ x }) => x\n  ? <Page>a</Page>\n  : <Page>b</Page>;"],
  ["one key twice", true, "function A({ x }) { if (x) return <Page key=\"k\">a</Page>; return <Page key=\"k\">b</Page>; }"],
  ["inside an element", true, "function A({ x }) { return <div>{x && <Page>a</Page>}{!x || <Page>b</Page>}{x ? <Page>c</Page> : <Page>d</Page>}</div>; }"],
  ["a helper", true, "function A({ p }) { const one = (q) => { if (q) return <Page>a</Page>; return <Page>b</Page>; };\n return <div>{one(p)}</div>; }"],
  ["a page component twice", true, "function Sub({ t }) { return <Page>{t}</Page>; }\nfunction A({ x }) { if (x) return <Sub t=\"a\" />; return <Sub t=\"b\" />; }"],
  ["a stack", false, "function A({ x }) { return (<>\n<Page key=\"root\">r</Page>\n{x && <Page key=\"x\">a</Page>}\n</>); }"],
  ["a loading frame", false, "function A({ s }) { if (!s) return <Page title=\"a\" back />; return <Page title=\"a\" back>{s}</Page>; }"],
  ["distinct keys", false, "function A({ x }) { if (x) return <Page key=\"a\">a</Page>; return <Page key=\"b\">b</Page>; }"],
  ["kinds apart", false, "function Sub() { return <Page>s</Page>; }\nfunction A({ x }) { if (x) return <Sub />; return <Page>b</Page>; }"],
  ["a page in a page", false, "function A({ x }) { return <Page>{x && <Page>a</Page>}</Page>; }"],
  ["callbacks and words", false, "function A({ l }) { const f = () => { return <Page>no</Page>; };\n if (l.some((x) => x > 1 && /<a>/.test(x))) return <p>it's {\"<\"} a / b</p>;\n return <ul>{l.map((x) => <Page key={x}>{x}</Page>)}</ul>; }"],
];
const blind = FIXTURES.filter(([, fails, src]) => (check([["fixture.jsx", PAGE + src]]).faults.length > 0) !== fails);
if (blind.length) {
  console.error(`pagekeys: the check reads its own cases wrong: ${blind.map(([n]) => n).join(", ")}`);
  process.exit(2);
}

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(process.argv[2] || join(here, "..", "src"));
const files = readdirSync(src).filter((f) => f.endsWith(".jsx")).sort();
let result;
try {
  result = check(files.map((f) => [f, readFileSync(join(src, f), "utf8")]));
} catch (e) {
  if (!(e instanceof Unread)) throw e;
  console.error(`pagekeys: cannot read ${e.message}`);
  process.exit(2);
}
const { all, kinds, faults, pages } = result;
console.log(`pagekeys: ${FIXTURES.length} cases of its own read right; ${files.length} files, ${all.length} components, ${kinds.size} of them pages, ${pages} page elements at their places (${src})`);
if (!faults.length) {
  console.log("pagekeys: every page stands at a place of its own or carries its own key");
  process.exit(0);
}
for (const { c, at, nodes } of faults) {
  const tag = nodes[0].tag;
  console.log(`  ${c.file}:${c.line} ${c.name}: <${tag}> at ${nodes.map((n) => n.line).join(", ")} can take one another's place (${at.split(" ")[0]})`);
}
console.log(`pagekeys: ${faults.length} place(s) where a page would hand its way out to the next -- give each page its own key, or keep the page under and push the other over it`);
process.exit(1);
