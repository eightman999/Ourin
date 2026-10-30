'use strict';
const selected = require('./entry-selection').script('.js', ['main.js', 'index.js']);
process.argv = [process.execPath, selected.file, ...selected.arguments];
require('node:module').runMain();
