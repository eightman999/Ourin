namespace MacUkagaka.SHIORI.Utils;

public static class SakuraScriptBuilder
{
    public static string Simple(string text)
        => $"\\h\\s[0]{text}\\e";
}
