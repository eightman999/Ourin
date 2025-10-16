using System.Collections.Generic;

namespace MacUkagaka.SHIORI.Models;

public class SHIORIRequest
{
    public string? Id { get; set; }
    public Dictionary<string,string> Headers { get; } = new();

    public string? GetReference(int index)
        => Headers.TryGetValue($"Reference{index}", out var v) ? v : null;

    public static SHIORIRequest Parse(string text)
    {
        var req = new SHIORIRequest();
        var lines = text.Split('\n');
        bool firstLine = true;
        
        foreach(var line in lines)
        {
            var trimmed = line.TrimEnd('\r');
            if(string.IsNullOrWhiteSpace(trimmed)) continue;
            
            if(firstLine)
            {
                // Parse request line: "GET Version SHIORI/3.0" or "GET String SHIORI/3.0"
                var parts = trimmed.Split(' ');
                if(parts.Length >= 2)
                {
                    req.Id = parts[1]; // "Version", "String", etc.
                }
                firstLine = false;
                continue;
            }
            
            var colon = trimmed.IndexOf(':');
            if(colon > 0)
            {
                var key = trimmed.Substring(0, colon).Trim();
                var val = trimmed[(colon + 1)..].Trim();
                req.Headers[key] = val;
                if(key == "ID") req.Id = val;
            }
        }
        return req;
    }
}
