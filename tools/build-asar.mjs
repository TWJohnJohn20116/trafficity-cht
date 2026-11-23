#!/usr/bin/env node
// Rebuild a Traditional Chinese (zht) patched app.asar from a pristine archive.
// Usage: node tools/build-asar.mjs <pristine app.asar> <output app.asar>
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SRC_ASAR = process.argv[2];
const OUT_ASAR = process.argv[3];
if (!SRC_ASAR || !OUT_ASAR) {
  console.error("usage: node tools/build-asar.mjs <pristine app.asar> <output app.asar>");
  process.exit(2);
}

const zhtPath = [path.join(__dirname, "..", "src", "zht.json"), path.join(__dirname, "..", "zht.json"), path.join(process.cwd(), "zht.json")]
  .find((p) => fs.existsSync(p));
if (!zhtPath) { console.error("zht.json not found (expected at src/zht.json)"); process.exit(2); }
const zht = JSON.parse(fs.readFileSync(zhtPath, "utf8"));

const fd = fs.openSync(SRC_ASAR, "r");
const probe = Buffer.alloc(16);
fs.readSync(fd, probe, 0, 16, 0);
const headerSize = probe.readUInt32LE(4);
const jsonLen = probe.readUInt32LE(12);
const DATA_BASE = 8 + headerSize;
const jsonBuf = Buffer.alloc(jsonLen);
fs.readSync(fd, jsonBuf, 0, jsonLen, 16);
const tree = JSON.parse(jsonBuf.toString("utf8"));

function walk(node, prefix, out) {
  for (const [name, v] of Object.entries(node.files)) {
    const p = prefix + "/" + name;
    if (v.files) walk(v, p, out);
    else out.push({ node: v, path: p });
  }
}
const entries = [];
walk(tree, "", entries);

const BUNDLE_RE = /^\/dist\/transit-city-game\.[0-9a-f]+\.js$/;
const targets = entries.filter((e) => BUNDLE_RE.test(e.path));
if (targets.length !== 1) { console.error("expected exactly one dist/transit-city-game.<hash>.js, found " + targets.length); process.exit(1); }
const target = targets[0];
const packed = entries.filter((e) => !e.node.unpacked && e.node.link === undefined);

function readEntry(e) {
  const size = e.origSize ?? Number(e.node.size);
  const srcOff = e.srcOffset ?? Number(e.node.offset);
  const buf = Buffer.alloc(size);
  fs.readSync(fd, buf, 0, buf.length, DATA_BASE + srcOff);
  return buf;
}

let src = readEntry(target).toString("utf8");
const before = Buffer.byteLength(src);

function scanLiteral(s, startIdx) {
  const open = s[startIdx];
  const close = open === "[" ? "]" : "}";
  let depth = 0, i = startIdx, inStr = null;
  for (; i < s.length; i++) {
    const ch = s[i];
    if (inStr) {
      if (ch === "\\") { i++; continue; }
      if (ch === inStr) inStr = null;
      continue;
    }
    if (ch === "\"" || ch === "'" || ch === String.fromCharCode(96)) { inStr = ch; continue; }
    if (ch === open) depth++;
    else if (ch === close) { depth--; if (depth === 0) return i + 1; }
  }
  throw new Error("unterminated literal");
}

if (src.includes(",zht:")) { console.error("this archive already contains the zht locale"); process.exit(1); }

const zhsIdx = src.indexOf("zhs:{");
if (zhsIdx < 0) throw new Error("zhs locale not found - unsupported game version");
const zhsOpen = src.indexOf("{", zhsIdx);
const zhsEnd = scanLiteral(src, zhsOpen);
src = src.slice(0, zhsEnd) + ",zht:" + JSON.stringify(zht) + src.slice(zhsEnd);

const nameOld = 'zhs:"\u7b80\u4f53\u4e2d\u6587"';
if (!src.includes(nameOld)) throw new Error("language name anchor missing");
src = src.replace(nameOld, nameOld + ',zht:"\u7e41\u9ad4\u4e2d\u6587"');

const steamOld = 'schinese:"zhs"';
if (!src.includes(steamOld)) throw new Error("steam language anchor missing");
src = src.replace(steamOld, 'schinese:"zhs",tchinese:"zht",traditionalchinese:"zht"');

const codeOld = 'zhs:"zh-CN"';
if (!src.includes(codeOld)) throw new Error("locale code anchor missing");
src = src.replace(codeOld, 'zhs:"zh-CN",zht:"zh-TW"');

const detOld = 'if("zh"===t)return c(n)&&g("zhs")?"zhs":null;';
if (!src.includes(detOld)) throw new Error("zh detection anchor missing");
src = src.replace(detOld, 'if("zh"===t){if(/^zh-(tw|hk|mo|hant)/.test(n))return g("zht")?"zht":null;return c(n)&&g("zhs")?"zhs":null}');

const patched = Buffer.from(src, "utf8");
target.node.size = patched.length;
console.log("bundle: " + before + " -> " + patched.length + " bytes");

const out = fs.openSync(OUT_ASAR, "w");
let offset = 0;
for (const e of packed) {
  e.srcOffset = Number(e.node.offset);
  e.origSize = Number(e.node.size);
  e.node.offset = String(offset);
  offset += Number(e.node.size);
}

let headerJson = JSON.stringify(tree);
let jsonBytes = Buffer.from(headerJson, "utf8");
const pad = (4 - ((4 + jsonBytes.length) % 4)) % 4;
if (pad) { headerJson += " ".repeat(pad); jsonBytes = Buffer.from(headerJson, "utf8"); }
const payloadLen = 4 + jsonBytes.length;
const headerSize2 = 4 + payloadLen;

const head = Buffer.alloc(16);
head.writeUInt32LE(4, 0);
head.writeUInt32LE(headerSize2, 4);
head.writeUInt32LE(payloadLen, 8);
head.writeUInt32LE(jsonBytes.length, 12);
fs.writeSync(out, head, 0, 16, 0);
fs.writeSync(out, jsonBytes, 0, jsonBytes.length, 16);

let pos = 16 + jsonBytes.length;
let bytes = 0;
for (const e of packed) {
  const buf = e === target ? patched : readEntry(e);
  fs.writeSync(out, buf, 0, buf.length, pos);
  pos += buf.length;
  bytes += buf.length;
}
fs.closeSync(out);
fs.closeSync(fd);
console.log("archive: " + pos + " bytes (" + packed.length + " files)");