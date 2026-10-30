using System.Text;
using System.Text.RegularExpressions;
using Kanahebi;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

// Only transport is replaced. ModuleMain executes the upstream IronPython script.
Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
if (args.Length != 0) throw new ArgumentException("Usage: KanahebiHost");
// IronPython opens OS fd 1 directly, so Console.SetOut alone cannot isolate print().
// Keep a private copy for protocol writes, redirect the original fd to stderr.
if (!OperatingSystem.IsMacOS()) throw new PlatformNotSupportedException("macOS SHIOLINK host");
int protocolFd = Posix.dup(1);
if (protocolFd < 0) throw new IOException("Cannot duplicate protocol stdout");
using var output = new FileStream(new SafeFileHandle((IntPtr)protocolFd, ownsHandle:true), FileAccess.Write);
if (Posix.dup2(2, 1) < 0) throw new IOException("Cannot isolate Python stdout");
Console.SetOut(Console.Error);
var input = Console.OpenStandardInput();
bool loaded = false;
byte[] ReadLine() {
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
    Environment.SetEnvironmentVariable("IRONPYTHONPATH", Path.Combine(AppContext.BaseDirectory, "Lib"));
    ModuleMain.NotifyModuleMode(UkastreamInterface.ModuleMode.SHIORI);
    ModuleMain.Load(path);
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
        var response = ModuleMain.RequestShiori(encoding.GetString(bytes));
        var responseEncoding = Charset(response, utf8);
        var payload = responseEncoding.GetBytes(response);
        if (payload.Length > 1048576 || !response.EndsWith("\r\n\r\n")) throw new FormatException("Malformed managed SHIORI response");
        Write(payload);
    }
} catch (EndOfStreamException) { }
finally { if (loaded) ModuleMain.Unload(); }

internal static class Posix {
    [DllImport("/usr/lib/libSystem.B.dylib", SetLastError=true)]
    internal static extern int dup(int descriptor);
    [DllImport("/usr/lib/libSystem.B.dylib", SetLastError=true)]
    internal static extern int dup2(int source, int destination);
}
