'use strict';
// Read an original Windows SHIOLINK setting as data. Never execute its command.
const fs = require('fs');
const path = require('path');

exports.tokens = function () {
  const names = fs.readdirSync('.');
  for (const preferred of ['shiolink.ourin.ini', 'shiolink.ini']) {
    const name = names.find(item => item.toLowerCase() === preferred);
    if (!name) continue;
    const text = fs.readFileSync(name, 'utf8');
    if (Buffer.byteLength(text) > 65536) throw new Error('SHIOLINK configuration exceeded limit');
    let active = true;
    for (const raw of text.split(/\r?\n/)) {
      const line = raw.trim();
      if (line.startsWith('[')) { active = line.toLowerCase() === '[shiolink]'; continue; }
      if (!active || /^[;#]/.test(line)) continue;
      const setting = line.match(/^commandline\s*=\s*(.*)$/i);
      if (setting) {
        if (/[\0\r\n]/.test(setting[1])) throw new Error('Invalid SHIOLINK command data');
        return (setting[1].match(/"[^"\r\n]*"|'[^'\r\n]*'|[^\s"']+/g) || [])
          .map(item => /^["']/.test(item) ? item.slice(1, -1) : item);
      }
    }
  }
  return [];
};

exports.localPath = function (value, directory = false) {
  const root = fs.realpathSync('.');
  const normalized = value.replace(/\\/g, '/');
  if (/[\0\r\n]/.test(normalized) || /^[A-Za-z]:/.test(normalized)) throw new Error('Invalid entry path');
  const candidate = fs.realpathSync(path.resolve(root, normalized));
  if (candidate !== root && !candidate.startsWith(root + path.sep)) throw new Error('Entry path leaves ghost directory');
  const stat = fs.statSync(candidate);
  if (directory ? !stat.isDirectory() : !stat.isFile()) throw new Error('Entry path type mismatch');
  return candidate;
};

exports.script = function (extension, fallbacks) {
  if (process.argv[2]) return { file: exports.localPath(process.argv[2]), arguments: process.argv.slice(3) };
  const tokens = exports.tokens();
  const index = tokens.findIndex(item => item.toLowerCase().endsWith(extension));
  if (index >= 0) return { file: exports.localPath(tokens[index]), arguments: tokens.slice(index + 1) };
  for (const filename of fallbacks) {
    if (fs.existsSync(filename)) return { file: exports.localPath(filename), arguments: [] };
  }
  throw new Error('Ghost entry script was not found');
};
