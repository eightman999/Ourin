require 'sana'
require 'shiolink'
class Events
def _load(path); $count = File.exist?('count.txt') ? File.read('count.txt').to_i : 0; end
def _unload; File.write('count.txt', $count.to_s); exit; end
def version(r); '0.0.4'; end
def OnBoot(r); $count += 1; "桜鈴 🌸 #{$count}"; end
def OnMouseDoubleClick(r); r.Reference0; end
def OnTest(r); nil; end
end
engine = Sana.new(Events.new)
Shiolink.new(engine.method(:load), engine.method(:unload), engine.method(:request)).start
