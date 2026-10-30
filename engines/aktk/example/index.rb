# Self-authored dictionary for the real aktk/mruby callbacks. No upstream example exists.
def _load(directory)
  $directory = directory
  path = directory + '/state.txt'
  $boots = File.exist?(path) ? File.open(path, 'r') { |file| file.read.to_i } : 0
  true
end

def _request(message)
  return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n" if message.start_with?('NOTIFY ')
  id = ''
  reference = ''
  message.split("\r\n").each do |line|
    id = line[4..-1] if line.start_with?('ID: ')
    reference = line[12..-1] if line.start_with?('Reference0: ')
  end
  case id
  when 'version' then value = '0.1'
  when 'name' then value = 'Ourin aktk mruby example'
  when 'OnBoot'
    $boots += 1
    value = "\\0\\s[0]mruby起動 #{$boots}。\\e"
  when 'OnEcho' then value = reference
  when 'OnClose' then value = '\0終了します。\-'
  when 'OnRaise' then raise 'expected dictionary error'
  when 'OnWrongType' then return 42
  else return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"
  end
  "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nSender: aktk\r\nValue: #{value}\r\n\r\n"
end

def _unload
  File.open($directory + '/state.txt', 'w') { |file| file.write($boots.to_s) }
  true
end
