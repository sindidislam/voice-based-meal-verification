// Minimal PDF text extractor: inflates FlateDecode streams and pulls Tj/TJ strings.
// Usage: node pdftext.js <input.pdf> <output.txt>
const fs = require('fs');
const zlib = require('zlib');

const inPath = process.argv[2];
const outPath = process.argv[3];
const buf = fs.readFileSync(inPath);

function findAll(hay, needle) {
  const out = [];
  let i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { out.push(i); i += needle.length; }
  return out;
}

const streamStarts = findAll(buf, Buffer.from('stream'));
const chunks = [];
for (const s of streamStarts) {
  // dict is before 'stream'
  const dictStart = buf.lastIndexOf(Buffer.from('<<'), s);
  const dict = buf.slice(Math.max(0, dictStart), s).toString('latin1');
  let p = s + 6;
  if (buf[p] === 0x0d) p++;
  if (buf[p] === 0x0a) p++;
  const e = buf.indexOf(Buffer.from('endstream'), p);
  if (e === -1) continue;
  let raw = buf.slice(p, e);
  if (!/FlateDecode/.test(dict)) continue;
  try {
    chunks.push(zlib.inflateSync(raw).toString('latin1'));
  } catch (err) {
    try { chunks.push(zlib.inflateRawSync(raw.slice(0)).toString('latin1')); } catch (e2) { /* skip */ }
  }
}

// Pull text-showing operators out of content streams
function decodeLiteral(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '\\') {
      const n = s[++i];
      if (n === 'n') out += '\n';
      else if (n === 'r') out += '\r';
      else if (n === 't') out += '\t';
      else if (n === 'b') out += '\b';
      else if (n === 'f') out += '\f';
      else if (n >= '0' && n <= '7') {
        let oct = n;
        while (oct.length < 3 && s[i + 1] >= '0' && s[i + 1] <= '7') oct += s[++i];
        out += String.fromCharCode(parseInt(oct, 8));
      } else out += n;
    } else out += c;
  }
  return out;
}

const lines = [];
for (const c of chunks) {
  if (!/(Tj|TJ|Td|TD|Tm)/.test(c)) continue;
  let text = '';
  // Tokenise: handle ( ... ) Tj  and  [ ... ] TJ  and  <hex> Tj
  const re = /\((?:\\.|[^\\()])*\)|<[0-9A-Fa-f\s]*>|\bT[jJdD*]\b|\bTm\b|\bET\b|\bTf\b|\bTL\b/g;
  let m;
  const toks = [];
  while ((m = re.exec(c)) !== null) toks.push(m[0]);
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i];
    if (t.startsWith('(')) {
      text += decodeLiteral(t.slice(1, -1));
    } else if (t.startsWith('<') && !t.startsWith('<<')) {
      const hex = t.slice(1, -1).replace(/\s+/g, '');
      // try 2-byte then 1-byte
      let s2 = '';
      if (hex.length % 4 === 0) {
        for (let k = 0; k < hex.length; k += 4) s2 += String.fromCharCode(parseInt(hex.substr(k, 4), 16));
      } else {
        for (let k = 0; k < hex.length; k += 2) s2 += String.fromCharCode(parseInt(hex.substr(k, 2), 16));
      }
      text += s2;
    } else if (t === 'Td' || t === 'TD' || t === 'T*' || t === 'Tm' || t === 'ET') {
      text += '\n';
    } else if (t === 'TJ' || t === 'Tj') {
      text += ' ';
    }
  }
  if (text.trim().length > 0) lines.push(text);
}

fs.writeFileSync(outPath, lines.join('\n\n----PAGE/STREAM----\n\n'), 'latin1');
console.log('streams:', chunks.length, 'text blocks:', lines.length, 'bytes:', fs.statSync(outPath).size);
