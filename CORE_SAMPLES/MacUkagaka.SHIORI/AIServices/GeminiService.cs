using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace MacUkagaka.SHIORI.AIServices;

public class GeminiService : IAIService
{
    private readonly string _apiKey;
    private readonly string _model;

    public GeminiService(string apiKey, string model)
    {
        _apiKey = apiKey;
        _model = string.IsNullOrEmpty(model) ? "gemini-pro" : model;
    }

    public async Task<string> GenerateResponseAsync(string prompt)
    {
        var endpoint = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
        var obj = new
        {
            contents = new[] { new { parts = new[] { new { text = prompt } } } }
        };
        var json = JsonSerializer.Serialize(obj);
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");
        using var client = new HttpClient();
        var response = await client.SendAsync(request);
        var str = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(str);
        var root = doc.RootElement;
        if (root.TryGetProperty("candidates", out var cand))
        {
            var text = cand[0].GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString();
            return text ?? str;
        }
        return str;
    }
}
