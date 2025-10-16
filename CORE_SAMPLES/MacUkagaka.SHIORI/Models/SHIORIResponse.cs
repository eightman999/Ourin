using System.Text;

namespace MacUkagaka.SHIORI.Models;

public class SHIORIResponse
{
    public string Status { get; set; } = "200 OK";
    public string Value { get; set; } = string.Empty;

    public override string ToString()
    {
        var sb = new StringBuilder();
        sb.AppendLine($"SHIORI/3.0 {Status}");
        sb.AppendLine("Charset: UTF-8");
        sb.AppendLine("Content-Type: text/plain");
        sb.AppendLine($"Value: {Value}");
        sb.AppendLine();
        return sb.ToString();
    }
}
