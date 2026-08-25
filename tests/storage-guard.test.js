// Regression test for the "Save does nothing" bug (docs/warden-storage-bug-fix.md).
//
// localStorage is only an offline MIRROR of Firestore here. When the origin's
// shared ~5MB budget fills, setItem throws QuotaExceededError — and because that
// call used to be the FIRST line of save(), the throw took out the whole
// function: the cloud save was never attempted and the Save button looked dead.
// These assertions fail if anyone reintroduces an unguarded mirror write.

const fs = require('fs');
const path = require('path');

const APPS = [{ file: 'warden.html', prefix: 'warden_kc_' }];

let pass = 0, fail = 0;
const ok = (n, c, e) => {
  if (c) { pass++; console.log('  ok   ' + n); }
  else { fail++; console.log('  FAIL ' + n + (e !== undefined ? '  -> ' + String(e).slice(0, 300) : '')); }
};

for (const app of APPS) {
  const p = path.join(__dirname, '..', app.file);
  if (!fs.existsSync(p)) continue;
  const src = fs.readFileSync(p, 'utf8');
  console.log('\n-- ' + app.file + ' --');

  const m = src.match(/function _kcMirror\([\s\S]{0,400}?\n\}/);
  ok('_kcMirror() is defined', !!m);
  ok('_kcMirror() wraps the write in try/catch',
     !!m && /try\s*\{[\s\S]*localStorage\.setItem[\s\S]*\}\s*catch/.test(m[0]));

  const direct = src.split('\n').map((l, i) => ({ l: l.trim(), n: i + 1 }))
    .filter(r => r.l.includes("localStorage.setItem('" + app.prefix));
  ok('no direct localStorage.setItem on the keychain keys', direct.length === 0,
     direct.map(r => app.file + ':' + r.n).join(' | '));

  const save = src.match(/function save\(\)\{[\s\S]{0,600}?\n\}/);
  ok('save() exists', !!save);
  if (save) {
    ok('save() mirrors via _kcMirror, not setItem', !/localStorage\.setItem/.test(save[0]));
    ok('save() still reaches _fbSaveKeychain', /_fbSaveKeychain/.test(save[0]));
  }

  const ar = src.match(/function applyRemote\(data\)\{[\s\S]{0,700}?\n  \}/);
  ok('applyRemote() exists', !!ar);
  if (ar) ok('applyRemote() mirrors via _kcMirror', !/localStorage\.setItem/.test(ar[0]));

  ok('icon cache has a byte cap', /KC_ICON_MAX_BYTES/.test(src));
  ok('an initial favicon sweep runs once the helpers exist', /kcInitialFaviconSweep/.test(src));
}

console.log('\n' + (fail ? 'FAILED ' + fail + ' of ' : 'ALL PASSED — ') + (pass + fail) + ' assertions');
process.exit(fail ? 1 : 0);
