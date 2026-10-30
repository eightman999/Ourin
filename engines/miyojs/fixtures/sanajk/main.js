const fs = require('fs');
const builder = new (require('sanajk').SanaShioriBuilder)().useDefaults();
let count = fs.existsSync('count.txt') ? Number(fs.readFileSync('count.txt', 'utf8')) : 0;
builder.state.events.OnBoot = () => `桜鈴 🌸 ${++count}`;
builder.state.events.OnMouseDoubleClick = ctx => ctx.request.headers.Reference(0);
const engine = builder.build();
const unload = engine.unload.bind(engine);
engine.unload = async () => { fs.writeFileSync('count.txt', String(count)); await unload(); process.exit(0); };
require('shiolinkjs').runShiori(engine);
