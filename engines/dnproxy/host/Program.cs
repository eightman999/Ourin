using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Ukagaka.NET.Interfaces;
using Ourin.DnProxyHost;

// This is a managed SHIOLINK host, not a loader for Windows PE exports.
// Public request(string) is required; guessing the Windows ANSI pointer ABI is unsafe.
Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
if (args.Length != 0 && args.Length != 2) throw new ArgumentException("Usage: DnProxyHost [--config dnproxy.ini | assembly.dll namespace.class]");
var output = Console.OpenStandardOutput();
Console.SetOut(Console.Error); // managed ghost diagnostics must not corrupt protocol stdout
var input = Console.OpenStandardInput();
object? module = null;
bool loaded = false;
IniCompiler? compiled = null;
byte[]? ReadLine() {
    var bytes = new List<byte>();
    while (true) {
        int b = input.ReadByte();
        if (b < 0) { if (bytes.Count == 0) return null; throw new EndOfStreamException(); }
        if (b == 10) break;
        bytes.Add((byte)b);
        if (bytes.Count > 1048576) throw new FormatException("SHIOLINK line exceeds limit");
    }
    if (bytes.Count > 0 && bytes[^1] == 13) bytes.RemoveAt(bytes.Count-1);
    return bytes.ToArray();
}
void Write(byte[] bytes) { output.Write(bytes); output.Flush(); }
Encoding Charset(string wire, Encoding fallback) {
    var m = Regex.Match(wire, @"(?im)^Charset:\s*([^\r\n]+)");
    return m.Success ? Encoding.GetEncoding(m.Groups[1].Value.Trim(), EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback) : fallback;
}
var utf8 = new UTF8Encoding(false, true);
try {
    var first = ReadLine();
    if (first == null) return;
    var load = utf8.GetString(first);
    if (!load.StartsWith("*L:")) throw new FormatException("Expected SHIOLINK load");
    var path = load.Substring(3);
    Directory.SetCurrentDirectory(path);
    bool fromConfig = args.Length == 0 || args[0] == "--config";
    if (fromConfig) compiled = IniCompiler.Build(Path.GetFullPath(args.Length == 0 ? "dnproxy.ini" : args[1], path));
    var assembly = fromConfig ? compiled!.Assembly : Assembly.LoadFrom(Path.GetFullPath(args[0]));
    var type = assembly.GetType(fromConfig ? compiled!.MainClass : args[1], throwOnError:true)!;
    if (!typeof(IShiori30).IsAssignableFrom(type)) throw new NotSupportedException("Requires the real IShiori30 interface");
    var request = type.GetMethod("request", new Type[]{ typeof(string) });
    if (request == null || request.ReturnType != typeof(string)) throw new NotSupportedException("Requires public string request(string), not Windows ANSI pointer marshalling");
    module = Activator.CreateInstance(type, nonPublic:true)!;
    var pointer = Marshal.StringToHGlobalAnsi(path); // Unix .NET ANSI is UTF-8; module owns/free's the buffer
    if (!((ILoad)module).load(pointer, utf8.GetByteCount(path))) throw new InvalidOperationException("Managed ghost load failed");
    loaded = true;
    while (true) {
        var raw = ReadLine();
        if (raw == null) break;
        var command = utf8.GetString(raw);
        if (command == "*U:") break;
        if (!command.StartsWith("*S:")) throw new FormatException("Expected SHIOLINK sync");
        Write(Encoding.ASCII.GetBytes(command+"\r\n"));
        using var frame = new MemoryStream();
        while (true) {
            var line = ReadLine() ?? throw new EndOfStreamException();
            frame.Write(line); frame.Write(new byte[]{13,10});
            if (frame.Length > 1048576) throw new FormatException("SHIORI frame exceeds limit");
            if (line.Length == 0) break;
        }
        var bytes = frame.ToArray();
        var encoding = Charset(Encoding.Latin1.GetString(bytes), utf8);
        var response = (string)request.Invoke(module,new object[]{encoding.GetString(bytes)})!;
        var responseEncoding = Charset(response, utf8);
        var payload = responseEncoding.GetBytes(response);
        if (payload.Length > 1048576 || !response.EndsWith("\r\n\r\n")) throw new FormatException("Malformed managed SHIORI response");
        Write(payload);
    }
} catch (EndOfStreamException) { }
catch (Exception error) { Console.Error.WriteLine(error); Environment.ExitCode = 1; }
finally { try { if (loaded && module is IUnload unload) unload.unload(); } finally { compiled?.Dispose(); } }
