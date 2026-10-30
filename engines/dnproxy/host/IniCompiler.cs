using System.Reflection;
using System.Runtime.Loader;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.VisualBasic;
using Microsoft.CodeAnalysis.Text;
using Ukagaka.NET.Interfaces;

namespace Ourin.DnProxyHost;

// POSIX adaptation of upstream dnutil/Compiler.cs's configuration contract.
// Compilation is performed by the actual C# / Visual Basic Roslyn compilers.
internal sealed class IniCompiler : IDisposable {
    readonly string temporary = Directory.CreateTempSubdirectory("ourin-dnproxy-module-").FullName;
    readonly Dictionary<string,string> dependencies = new(StringComparer.OrdinalIgnoreCase);
    public Assembly Assembly { get; private set; } = null!;
    public string MainClass { get; private set; } = "";
    IniCompiler() { }

    static string LocalPath(string root, string value) {
        value = value.Replace('\\', Path.DirectorySeparatorChar);
        if (value.Length > 1 && value[1] == ':') throw new NotSupportedException("Windows drive paths require a POSIX configuration: " + value);
        return Path.GetFullPath(value, root);
    }

    // Match the original colon keys, continuation lines, comma lists and // comments.
    static Dictionary<string,List<string>> ReadSettings(string path) {
        var result = new Dictionary<string,List<string>>(StringComparer.OrdinalIgnoreCase);
        string? key = null;
        foreach (var raw in File.ReadLines(path, Encoding.UTF8)) {
            var line = raw.Split(new[]{"//"}, 2, StringSplitOptions.None)[0].Trim();
            if (line.Length == 0) continue;
            int colon = line.IndexOf(':');
            if (colon >= 0) { key = line[..colon].Trim(); line = line[(colon+1)..].Trim(); }
            if (key == null || line.Length == 0) continue;
            if (!result.TryGetValue(key, out var entries)) result[key] = entries = new();
            entries.Add(line);
        }
        return result;
    }

    static IEnumerable<string> Expand(string root, IEnumerable<string> values, bool assemblyNames = false) {
        foreach (var value in values.SelectMany(v => v.Split(',')).Select(v => v.Trim()).Where(v => v.Length != 0)) {
            var pieces = value.Split('|');
            var path = LocalPath(root, pieces[0]);
            if (pieces.Length > 2) throw new FormatException("Invalid directory|pattern: " + value);
            if (pieces.Length == 2 || Directory.Exists(path)) {
                if (!Directory.Exists(path)) throw new FileNotFoundException("Configured directory is missing", path);
                foreach (var file in Directory.EnumerateFiles(path, pieces.Length == 2 ? pieces[1] : "*.*",
                    new EnumerationOptions { RecurseSubdirectories = true, MatchCasing = MatchCasing.CaseInsensitive })) yield return file;
            } else if (File.Exists(path)) yield return path;
            else if (assemblyNames) yield return value;
            else throw new FileNotFoundException("Configured file is missing", path);
        }
    }

    Assembly? Resolve(AssemblyLoadContext context, AssemblyName name) {
        return name.Name != null && dependencies.TryGetValue(name.Name, out var file) ? context.LoadFromAssemblyPath(file) : null;
    }

    public static IniCompiler Build(string config) {
        var compiled = new IniCompiler();
        try { compiled.Compile(Path.GetFullPath(config)); return compiled; }
        catch { compiled.Dispose(); throw; }
    }

    void Compile(string config) {
        var settings = ReadSettings(config);
        string root = Path.GetDirectoryName(config)!;
        string Value(string key, string fallback = "") => settings.TryGetValue(key, out var v) ? v[^1] : fallback;
        IEnumerable<string> Entries(string key) => settings.TryGetValue(key, out var v) ? v : Enumerable.Empty<string>();
        bool Flag(string key, bool fallback = false) => Value(key) is { Length: > 0 } v ? int.Parse(v) != 0 : fallback;
        var known = new HashSet<string>(new[]{"Language","SourceFiles","MainClass","OutputAssembly","GenerateExecutable",
            "GenerateInMemory","IncludeDebugInformation","CompilerOptions","WarningLevel","TreatWarningsAsErrors",
            "ReferencedAssemblies","EmbeddedResources","LinkedResources","Win32Resource"}, StringComparer.OrdinalIgnoreCase);
        foreach (var key in settings.Keys) if (!known.Contains(key)) throw new NotSupportedException("Unsupported dnproxy.ini key: " + key);
        if (Flag("GenerateExecutable")) throw new NotSupportedException("Only managed SHIORI libraries are supported, not GenerateExecutable");
        if (Value("Win32Resource").Length != 0 || Entries("LinkedResources").Any())
            throw new NotSupportedException("Win32Resource / LinkedResources are outside the managed host contract");
        // Both modes have process-isolated lifetime. Disk output never overwrites the ghost.
        _ = Flag("GenerateInMemory", true);
        MainClass = Value("MainClass", "Unknown.User");
        if (MainClass.Length == 0) throw new FormatException("MainClass must not be empty");
        var sources = Expand(root, Entries("SourceFiles")).Distinct().Order().ToArray();
        if (sources.Length == 0) throw new FormatException("SourceFiles must select at least one source");
        var platform = ((string?)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES") ?? "").Split(Path.PathSeparator)
            .Where(File.Exists).Distinct().ToArray();
        var references = platform.ToDictionary(f => Path.GetFileName(f), f => f, StringComparer.OrdinalIgnoreCase);
        references["Ukagaka.NET.Interfaces.dll"] = typeof(IShiori30).Assembly.Location;
        references["dnutil.dll"] = typeof(D.N.Logger).Assembly.Location;
        foreach (var item in Expand(root, Entries("ReferencedAssemblies"), assemblyNames:true)) {
            var name = Path.GetFileName(item);
            // Map framework facades, the original interface, and our real Logger port.
            if (references.ContainsKey(name)) continue;
            var file = LocalPath(root, item);
            if (!File.Exists(file)) throw new FileNotFoundException("Referenced assembly is unavailable on .NET 10", file);
            var assemblyName = AssemblyName.GetAssemblyName(file).Name!;
            dependencies[assemblyName] = file;
            references[name] = file;
        }
        var metadata = references.Values.Distinct().Select(file => MetadataReference.CreateFromFile(file)).ToArray();
        var options = CommandLineParser.SplitCommandLineIntoArguments(Value("CompilerOptions"), removeHashComments:false)
            .Concat(new[]{"/target:library", "/out:" + Path.Combine(temporary, "user.dll")}).Concat(sources);
        string language = Value("Language").ToLowerInvariant();
        CommandLineArguments parsed = language switch {
            "csharp" or "c#" or "cs" => CSharpCommandLineParser.Default.Parse(options, root, sdkDirectory:Path.GetDirectoryName(typeof(object).Assembly.Location)),
            "visualbasic" or "vb" or "vb.net" => VisualBasicCommandLineParser.Default.Parse(options, root, sdkDirectory:Path.GetDirectoryName(typeof(object).Assembly.Location)),
            _ => throw new NotSupportedException("Unsupported Language: " + Value("Language"))
        };
        if (parsed.Errors.Any(d => d.Severity == DiagnosticSeverity.Error)) throw new FormatException(string.Join("\n", parsed.Errors));
        if (parsed.SourceFiles.Any(f => !sources.Contains(f.Path)) ||
            parsed.MetadataReferences.Any(r => !references.ContainsKey(Path.GetFileName(r.Reference))) ||
            parsed.ManifestResources.Any() || parsed.AnalyzerReferences.Any())
            throw new NotSupportedException("Put source files, references and resources in their dnproxy.ini keys, not CompilerOptions");
        var encoding = parsed.Encoding ?? new UTF8Encoding(false, true);
        var texts = sources.Select(file => (path:file, text:SourceText.From(File.ReadAllText(file, encoding), encoding))).ToArray();
        var nameStem = Path.GetFileNameWithoutExtension(Value("OutputAssembly", "user.dll"));
        if (string.IsNullOrWhiteSpace(nameStem)) nameStem = "user";
        var warning = Flag("TreatWarningsAsErrors") ? ReportDiagnostic.Error : ReportDiagnostic.Default;
        VisualBasicParseOptions? vbParse = null;
        if (parsed is VisualBasicCommandLineArguments vbArguments) {
            // Match .NET SDK's VisualBasic targets: _MyType="Empty" for portable
            // libraries, rather than injecting desktop My.Application/Devices.
            var symbols = vbArguments.ParseOptions.PreprocessorSymbols.ToArray();
            var myType = symbols.FirstOrDefault(s => s.Key.Equals("_MYTYPE", StringComparison.OrdinalIgnoreCase));
            if (myType.Key != null && !Equals(myType.Value, "Empty")) throw new NotSupportedException("Desktop VB MyType is not supported");
            vbParse = myType.Key == null ? vbArguments.ParseOptions.WithPreprocessorSymbols(symbols.Append(new KeyValuePair<string,object>("_MYTYPE", "Empty"))) : vbArguments.ParseOptions;
        }
        Compilation compilation = parsed switch {
            CSharpCommandLineArguments cs => CSharpCompilation.Create(nameStem,
                texts.Select(t => CSharpSyntaxTree.ParseText(t.text, cs.ParseOptions, t.path)), metadata,
                cs.CompilationOptions.WithOutputKind(OutputKind.DynamicallyLinkedLibrary)
                    .WithWarningLevel(int.Parse(Value("WarningLevel", "4"))).WithGeneralDiagnosticOption(warning)),
            VisualBasicCommandLineArguments vb => VisualBasicCompilation.Create(nameStem,
                texts.Select(t => VisualBasicSyntaxTree.ParseText(t.text, vbParse!, t.path)), metadata,
                vb.CompilationOptions.WithParseOptions(vbParse!).WithOutputKind(OutputKind.DynamicallyLinkedLibrary).WithGeneralDiagnosticOption(warning)),
            _ => throw new NotSupportedException()
        };
        var resources = Expand(root, Entries("EmbeddedResources")).Select(file =>
            new ResourceDescription(Path.GetFileName(file), () => File.OpenRead(file), isPublic:true)).ToArray();
        string output = Path.Combine(temporary, nameStem + ".dll");
        using (var pe = File.Create(output)) {
            using var pdb = Flag("IncludeDebugInformation") ? File.Create(Path.ChangeExtension(output, ".pdb")) : null;
            var emitted = compilation.Emit(pe, pdb, manifestResources:resources,
                options:parsed.EmitOptions.WithDebugInformationFormat(Microsoft.CodeAnalysis.Emit.DebugInformationFormat.PortablePdb));
            foreach (var diagnostic in emitted.Diagnostics) Console.Error.WriteLine(diagnostic);
            if (!emitted.Success) throw new InvalidOperationException("D.N.Proxy source compilation failed");
        }
        AssemblyLoadContext.Default.Resolving += Resolve;
        Assembly = AssemblyLoadContext.Default.LoadFromAssemblyPath(output);
    }

    public void Dispose() {
        AssemblyLoadContext.Default.Resolving -= Resolve;
        Directory.Delete(temporary, recursive:true);
    }
}
