// Structural check for the generated single-file HTML deliverables.
//   node tools/checkhtml.js MEAL_SYSTEM_MANUAL.html
// Reports leftover build placeholders, unresolved internal anchors, and any
// element whose open and close counts disagree.  It is deliberately crude: the
// deliverables are generated, so the failure mode worth catching is a chunked
// append that dropped a closing tag, not subtle nesting.
const fs = require('fs');

const VOID = new Set(['br', 'hr', 'img', 'input', 'meta', 'link', 'source']);

function check(file) {
  const h = fs.readFileSync(file, 'utf8');
  let bad = 0;
  console.log('--- ' + file);
  console.log('    ' + h.length + ' bytes, ' + h.split('\n').length + ' lines');

  const placeholders = h.match(/<!--\s*(BODY|CSS\d*|TODO|SLIDES?\d*)\s*-->/g);
  if (placeholders) { console.log('    FAIL leftover placeholders: ' + placeholders.join(', ')); bad++; }

  const ids = new Set();
  for (const m of h.matchAll(/\sid="([^"]+)"/g)) ids.add(m[1]);
  const missing = new Set();
  for (const m of h.matchAll(/href="#([^"]+)"/g)) if (!ids.has(m[1])) missing.add(m[1]);
  if (missing.size) { console.log('    FAIL unresolved anchors: ' + [...missing].join(', ')); bad++; }

  const opens = new Map();
  const closes = new Map();
  for (const m of h.matchAll(/<([a-zA-Z][a-zA-Z0-9]*)(\s[^>]*)?>/g)) {
    const t = m[1].toLowerCase();
    if (VOID.has(t)) continue;
    opens.set(t, (opens.get(t) || 0) + 1);
  }
  for (const m of h.matchAll(/<\/([a-zA-Z][a-zA-Z0-9]*)\s*>/g)) {
    const t = m[1].toLowerCase();
    closes.set(t, (closes.get(t) || 0) + 1);
  }
  for (const t of new Set([...opens.keys(), ...closes.keys()])) {
    const o = opens.get(t) || 0;
    const c = closes.get(t) || 0;
    if (o !== c) { console.log('    FAIL <' + t + '> open ' + o + ' close ' + c); bad++; }
  }

  const secs = [...h.matchAll(/class="sec" id="(s\d+)"/g)].map(m => m[1]);
  if (secs.length) console.log('    sections: ' + secs.join(' '));
  const slides = (h.match(/class="slide"/g) || []).length;
  if (slides) console.log('    slides: ' + slides);

  console.log(bad === 0 ? '    OK' : '    ' + bad + ' problem(s)');
  return bad;
}

let total = 0;
for (const f of process.argv.slice(2)) total += check(f);
process.exit(total === 0 ? 0 : 1);
