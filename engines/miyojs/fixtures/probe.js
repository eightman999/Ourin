// Ourin's own MiyoDictionary fixture; upstream engine sources are unchanged.
const fs = require('fs');
module.exports = {
  restore: {
    type: 'through',
    filter(argument) {
      this.default_response_headers = { Charset: 'UTF-8', Sender: 'MiyoJS' };
      this.ourinCount = fs.existsSync('count.txt') ? Number(fs.readFileSync('count.txt', 'utf8')) : 0;
      return argument;
    },
  },
  counter: {
    type: 'data-value',
    filter() { return `桜鈴 🌸 ${++this.ourinCount}`; },
  },
  echo: {
    type: 'data-value',
    filter(argument, request) { return request.headers.get('Reference0'); },
  },
  save: {
    type: 'data-value',
    filter() { fs.writeFileSync('count.txt', String(this.ourinCount)); return ''; },
  },
};
