using System.Collections.Generic;
using System;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using D.N;
using Ukagaka.NET.Interfaces;

namespace Ourin.DnProxy;
public class ProbeGhost : MarshalByRefObject, IShiori30 {
    string root = "";
    int boots;
    public bool load(IntPtr input, int length) {
        try { root=Marshal.PtrToStringAnsi(input,length)!; }
        finally { Marshal.FreeHGlobal(input); }
        var save=Path.Combine(root,"dnproxy-save.json");
        if (File.Exists(save)) boots=JsonSerializer.Deserialize<int>(File.ReadAllText(save));
        Logger.LogType=2; Logger.LogLevel=Logger.Level.ALL; Logger.LogCharset=Logger.Charset.UTF8;
        Logger.Initialize(root); Logger.WriteLine(Logger.Level.INFO,"load: 桜鈴");
        File.WriteAllText(Path.Combine(root,"dnproxy-loaded.path"),root);
        return true;
    }
    public bool unload() {
        File.WriteAllText(Path.Combine(root,"dnproxy-save.json"),JsonSerializer.Serialize(boots));
        Logger.WriteLine(Logger.Level.INFO,"unload: 桜鈴"); Logger.Finalize(); return true;
    }
    public string request(string wire) {
        var headers=wire.Split("\r\n").Where(s=>s.Contains(": ")).ToDictionary(s=>s[..s.IndexOf(": ")],s=>s[(s.IndexOf(": ")+2)..]);
        string id=headers.GetValueOrDefault("ID","");
        string? value=id switch { "version"=>"1.0", "OnBoot"=>"桜鈴 🌸 "+(++boots), "OnEcho"=>headers.GetValueOrDefault("Reference0",""), "OnClose"=>"終了します。", _=>null };
        if (wire.StartsWith("NOTIFY ")) value=null;
        return "SHIORI/3.0 "+(value==null?"204 No Content":"200 OK")+"\r\nCharset: UTF-8\r\n"+(value==null?"":"Value: "+value+"\r\n")+"\r\n";
    }
    public IntPtr request(IntPtr input,ref int length) {
        string wire;
        try { wire=Marshal.PtrToStringAnsi(input,length)!; }
        finally { Marshal.FreeHGlobal(input); }
        var response=request(wire); length=Encoding.UTF8.GetByteCount(response);
        return Marshal.StringToHGlobalAnsi(response);
    }
}
