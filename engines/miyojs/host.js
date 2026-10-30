'use strict';
// Serial line framing for upstream MiyoJS and its actual legacy SHIOLINK parser.
// The original entrypoint treats arbitrary pipe chunks as complete lines and
// starts overlapping promise chains. Keep dictionary/engine behavior unchanged.
const readline = require('readline');
const selection = require('./entry-selection');
const Miyo = require('./packages/node_modules/miyojs');
const Shiolink = require('./packages/node_modules/miyojs/node_modules/shiolinkjs');
const tokens = selection.tokens();
const entry = tokens.findIndex(item => /miyo-shiolink\.js$/i.test(item.replace(/\\/g, '/')));
const directory = selection.localPath(process.argv[2] || (entry >= 0 ? tokens[entry + 1] : '.') || '.', true);
const engine = new Miyo(Miyo.DictionaryLoader.load_recursive(directory));
const link = new Shiolink(engine);
const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
let queue = Promise.resolve();
lines.on('line', line => {
  queue = queue.then(async () => {
    if (Buffer.byteLength(line, 'utf8') > 1048576) throw new Error('SHIOLINK line exceeded limit');
    const response = await link.add_line(line);
    if (response != null) process.stdout.write(response);
  }).catch(error => { console.error(error); process.exit(1); });
});
lines.on('close', () => { queue.then(() => engine.unload()).catch(error => { console.error(error); process.exit(1); }); });
