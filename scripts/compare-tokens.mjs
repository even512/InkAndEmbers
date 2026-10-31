// Verifies that comment-only edits left the Lua code untouched: compares the token
// stream (comments and whitespace dropped) of each file against a git ref, plus the
// parsed AST (without positions) as a second check.
// Usage: node scripts/compare-tokens.mjs [ref=master] [dir=addon] [--flat]  (--flat: no subdirectories; line endings are normalised)
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ref = process.argv[2] || "master";
const dir = (process.argv[3] || "addon").split("\\").join("/");

const stripCR = (s) => s.replaceAll(String.fromCharCode(13), "");

function collect(rel, flat = false) {
  const out = [];
  for (const e of readdirSync(path.join(ROOT, rel), { withFileTypes: true })) {
    const r = `${rel}/${e.name}`;
    if (e.isDirectory()) { if (!flat) out.push(...collect(r)); }
    else if (e.name.endsWith(".lua")) out.push(r);
  }
  return out.sort();
}

// Matches a long bracket opener like [[ or [==[ at position i; returns its level or -1.
function longLevel(s, i) {
  if (s[i] !== "[") return -1;
  let j = i + 1;
  while (s[j] === "=") j++;
  return s[j] === "[" ? j - i - 1 : -1;
}

function tokens(s) {
  const out = [];
  let i = 0;
  const n = s.length;
  while (i < n) {
    const c = s[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === "-" && s[i + 1] === "-") {
      const lvl = longLevel(s, i + 2);
      if (lvl >= 0) {
        const end = s.indexOf("]" + "=".repeat(lvl) + "]", i + 2);
        i = end < 0 ? n : end + lvl + 2;
      } else {
        while (i < n && s[i] !== "\n") i++;
      }
      continue;
    }
    const lvl = longLevel(s, i);
    if (lvl >= 0) {
      const end = s.indexOf("]" + "=".repeat(lvl) + "]", i);
      const stop = end < 0 ? n : end + lvl + 2;
      out.push(s.slice(i, stop));
      i = stop;
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1;
      while (j < n && s[j] !== c) j += s[j] === "\\" ? 2 : 1;
      out.push(s.slice(i, j + 1));
      i = j + 1;
      continue;
    }
    let m = /^(?:0[xX][0-9a-fA-F.]+(?:[pP][+-]?\d+)?|\d[\d.]*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/.exec(s.slice(i, i + 64));
    if (!m) m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(s.slice(i, i + 256));
    if (!m) m = /^(?:\.\.\.|\.\.|==|~=|<=|>=|::|.)/.exec(s.slice(i, i + 4));
    out.push(m[0]);
    i += m[0].length;
  }
  return out;
}

function ast(src) {
  return JSON.stringify(luaparse.parse(src, { luaVersion: "5.1", comments: false, locations: false, ranges: false }));
}

let bad = 0;
const flat = process.argv.includes("--flat");
const files = collect(dir, flat);
for (const rel of files) {
  const now = stripCR(readFileSync(path.join(ROOT, rel), "utf8"));
  let before;
  try {
    before = execFileSync("git", ["show", `${ref}:${rel}`], { cwd: ROOT, encoding: "utf8", maxBuffer: 1 << 28 });
  } catch {
    console.log(`SKIP  ${rel} (not in ${ref})`);
    continue;
  }
  const a = tokens(stripCR(before));
  const b = tokens(now);
  const tokOk = a.length === b.length && a.every((x, i) => x === b[i]);
  const astOk = ast(stripCR(before)) === ast(now);
  const ok = tokOk && astOk;
  console.log(`${ok ? "OK  " : "DIFF"} ${rel}  (${a.length} tokens)`);
  if (!ok) bad++;
}
console.log(bad ? `${bad} file(s) differ` : `all ${files.length} files identical`);
process.exit(bad ? 1 : 0);
