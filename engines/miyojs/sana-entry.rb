# Use the bundled Ruby with an original ghost entry; never run the Windows command.
root = File.realpath(Dir.pwd)
tokens = []
%w[shiolink.ourin.ini shiolink.ini].each do |preferred|
  name = Dir.children('.').find { |item| item.downcase == preferred }
  next unless name
  raise 'SHIOLINK configuration exceeded limit' if File.size(name) > 65_536
  active = true
  File.read(name, encoding: 'UTF-8').each_line do |raw|
    line = raw.strip
    if line.start_with?('[')
      active = line.downcase == '[shiolink]'
      next
    end
    next unless active
    match = line.match(/^commandline\s*=\s*(.*)$/i)
    next unless match
    tokens = match[1].scan(/"[^"\r\n]*"|'[^'\r\n]*'|[^\s"']+/).map { |item| item.match?(/\A["']/) ? item[1...-1] : item }
    break
  end
  break unless tokens.empty?
end
if ARGV.empty?
  index = tokens.index { |item| item.downcase.end_with?('.rb') }
  if index
    script = tokens[index]
    ARGV.replace(tokens[(index + 1)..])
  else
    script = %w[main.rb index.rb].find { |name| File.file?(name) }
  end
else
  script = ARGV.shift
end
raise 'Ghost Ruby entry was not found' unless script
script = script.tr('\\', '/')
raise 'Invalid entry path' if script.match?(/[\x00\r\n]/) || script.match?(/\A[A-Za-z]:/)
entry = File.realpath(script)
raise 'Entry path leaves ghost directory' unless entry.start_with?(root + File::SEPARATOR) && File.file?(entry)
$PROGRAM_NAME = entry
load entry
