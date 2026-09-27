// Exercises the actual QML JavaScript helpers; rendering still needs Quickshell.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const qml = fs.readFileSync(path.join(__dirname, '../files/quickshell-picker/shell.qml'), 'utf8');
const context = vm.createContext({ themeColors: {} });
for (const name of ['loadTheme', 'fileUrl', 'parseRows', 'indexForSelected']) {
  const match = qml.match(new RegExp('^  function ' + name + '\\([^]*?^  }', 'm'));
  assert.ok(match, name);
  vm.runInContext(match[0], context);
}

const green = { selectedBorder: '#00aa00', unselectedBorder: '#202020', foreground: '#eeeeee' };
const rose = { selectedBorder: '#ff0088', unselectedBorder: '#bbbbbb', foreground: '#111111' };
for (const colors of [green, rose]) {
  context.loadTheme(JSON.stringify(colors));
  assert.equal(JSON.stringify(context.themeColors), JSON.stringify(colors));
}
for (const bad of ['', '{', 'null', '[]', '{}', '{"selectedBorder":"blue"}',
                   JSON.stringify({ ...green, foreground: '#xyzxyz' })]) {
  context.loadTheme(bad);
  assert.equal(JSON.stringify(context.themeColors), JSON.stringify(rose));
}
context.loadTheme(JSON.stringify(green));
assert.equal(context.themeColors.selectedBorder, green.selectedBorder);

const rows = context.parseRows(JSON.stringify({
  items: [{ path: '/first.png', label: 'first' }, { path: '/chosen.png', label: 'chosen' }],
  selected: '/chosen.png'
}));
assert.equal(context.indexForSelected(rows.items, rows.selected), 1);
assert.equal(context.indexForSelected(rows.items, '/removed.png'), 0);
assert.equal(context.parseRows('{').items.length, 0);
for (const name of ['/pictures/a #b?c%20.png', '/pictures/space café.png']) {
  const url = new URL(context.fileUrl(name));
  assert.equal(decodeURIComponent(url.pathname), name);
  assert.equal(url.search, '');
  assert.equal(url.hash, '');
}
console.log('PASS: theme changes/recovery, current selection, escaped image URLs');
