import fs from "node:fs";
import path from "node:path";
const ASAR = process.argv[2];
const MODE = process.argv[3] || "list";
const fd = fs.openSync(ASAR, "r");
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
    else out.push({ path: p, size: Number(v.size ?? 0), offset: v.offset != null ? Number(v.offset) : null, unpacked: !!v.unpacked, link: v.link || null });
  }
}
const files = [];
walk(tree, "", files);
if (MODE === "list") {
  const total = files.reduce((a, b) => a + b.size, 0);
  console.log(JSON.stringify({ dataBase: DATA_BASE, headerSize, jsonLen, count: files.length, totalBytes: total }));
  for (const f of files) if (/\.(js|html|css|json|txt)$/i.test(f.path)) console.log(f.size, f.path);
} else if (MODE === "textout") {
  const outDir = process.argv[4];
  const re = /\.(js|html|css|txt)$/i;
  const hits = files.filter(f => re.test(f.path) && f.offset != null);
  let n = 0, bytes = 0;
  for (const f of hits) {
    const buf = Buffer.alloc(f.size);
    fs.readSync(fd, buf, 0, f.size, DATA_BASE + f.offset);
    const dest = path.join(outDir, f.path);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, buf);
    n++; bytes += f.size;
  }
  console.log(JSON.stringify({ extracted: n, bytes, dataBase: DATA_BASE }));
}