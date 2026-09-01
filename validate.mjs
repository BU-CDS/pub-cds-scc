// validate.mjs — smoke-test the built public cluster page (DOM-shim runner,
// copied from cpu-cds-scc/validate.mjs; the pattern is portal-agnostic).
//
// The R build only checks R syntax; it cannot see runtime JS errors in the
// inlined script (TDZ / forward const refs, undefined symbols, bad data
// access), which ship as a silently BLANK page. This executes the page's own
// JS under a minimal DOM shim and exits non-zero on any runtime throw, so
// refresh_public.sh can fail (and alert) instead of publishing a dead page.
//
// Usage: node validate.mjs <index.html>   (exit 0 = clean, 1 = JS threw, 2 = usage)
import { readFileSync } from 'node:fs';

const path = process.argv[2];
if (!path) { console.error('usage: node validate.mjs <index.html>'); process.exit(2); }

const html = readFileSync(path, 'utf8');
const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n;\n');
if (!scripts.trim()) { console.error('validate: no <script> content found'); process.exit(1); }

// minimal DOM/BOM shim: enough for the page's init + render to run without a browser
const stub = new Proxy({}, {
  get(_t, p) {
    if (p === 'style') return {};
    if (p === 'classList') return { toggle() {}, add() {}, remove() {}, contains() { return false; } };
    if (p === 'querySelectorAll') return () => [];
    if (p === 'querySelector') return () => stub;
    if (p === 'dataset') return {};
    if (['appendChild', 'setAttribute', 'addEventListener', 'removeEventListener',
         'focus', 'click', 'insertAdjacentHTML', 'remove'].includes(p)) return () => {};
    if (['textContent', 'innerHTML', 'value', 'className'].includes(p)) return '';
    return undefined;
  },
  set() { return true; },
});
// HONEST element lookup: a selector that cannot match the page's static markup
// returns null, exactly as a browser does at init. This catches unguarded wiring
// of stripped/optional elements (a never-null stub shipped a blank public page:
// $('#lb').onclick threw on the build that removed the #lb aside). Elements the
// JS creates at runtime are expected to be null-checked by their own call sites.
const IDS = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]));
const CLS = new Set([...html.matchAll(/\bclass="([^"]+)"/g)].flatMap(m => m[1].split(/\s+/)));
const present = sel => {
  if (typeof sel !== 'string') return true;
  const id = sel.match(/#([\w-]+)/);           // first id token decides; descendant parts ride the stub
  if (id) return IDS.has(id[1]);
  const cl = sel.match(/\.([\w-]+)/);
  if (cl) return CLS.has(cl[1]);
  return true;                                  // bare tag/other selectors: permissive
};
const document = { getElementById: i => (IDS.has(i) ? stub : null),
                   querySelector: s => (present(s) ? stub : null), querySelectorAll: () => [],
                   createElement: () => stub, addEventListener: () => {}, body: stub };
const window = { addEventListener: () => {}, matchMedia: () => ({ matches: false, addEventListener: () => {} }) };
const localStorage = { getItem: () => null, setItem: () => {} };

try {
  // setInterval/clearInterval are shadowed with stubs: the page's auto-advance
  // would otherwise arm a real Node timer and keep this validator alive forever.
  new Function('document', 'window', 'localStorage', 'matchMedia', 'setInterval', 'clearInterval', scripts)(
    document, window, localStorage, window.matchMedia, () => 0, () => {});
  console.log('validate: page JS executed cleanly');
} catch (e) {
  console.error('validate: PAGE JS THREW -> ' + (e && e.message ? e.message : e));
  process.exit(1);
}
