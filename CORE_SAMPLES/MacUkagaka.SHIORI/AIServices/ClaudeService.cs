using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace MacUkagaka.SHIORI.AIServices;

public class ClaudeService : IAIService
{
    private readonly string _apiKey;
    private readonly string _model;

    public ClaudeService(string apiKey, string model)
    {
        _apiKey = apiKey;
        _model = string.IsNullOrEmpty(model) ? "claude-3-haiku-20240307" : model;
    }

    public async Task<string> GenerateResponseAsync(string prompt)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey))
                return "Error: Claude API key not configured";
                
            if (string.IsNullOrEmpty(prompt))
                return "Error: Empty prompt";

            var endpoint = "https://api.anthropic.com/v1/messages";
            var obj = new
            {
                model = _model,
                max_tokens = 1024,
                messages = new[]
                {
                    new { role = "user", content = prompt }
                }
            };
            var json = JsonSerializer.Serialize(obj);
            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
            request.Content = new StringContent(json, Encoding.UTF8, "application/json");
            request.Headers.Add("X-API-Key", _apiKey);
            request.Headers.Add("anthropic-version", "2023-06-01");
            
            using var client = new HttpClient();
            client.Timeout = TimeSpan.FromSeconds(30);
            
            var response = await client.SendAsync(request);
            var str = await response.Content.ReadAsStringAsync();
            
            if (!response.IsSuccessStatusCode)
            {
                Console.Error.WriteLine($"Claude API error: {response.StatusCode} - {str}");
                return $"Error: Claude API returned {response.StatusCode}";
            }
            
            using var doc = JsonDocument.Parse(str);
            if (doc.RootElement.TryGetProperty("content", out var content) && content.GetArrayLength() > 0)
            {
                var firstContent = content[0];
                if (firstContent.TryGetProperty("text", out var text))
                    return text.GetString() ?? "Error: Empty response from Claude";
            }
            
            Console.Error.WriteLine($"Unexpected Claude response format: {str}");
            return "Error: Unexpected response format from Claude";
        }
        catch (HttpRequestException ex)
        {
            Console.Error.WriteLine($"Network error calling Claude API: {ex.Message}");
            return "Error: Network problem connecting to Claude";
        }
        catch (TaskCanceledException ex)
        {
            Console.Error.WriteLine($"Claude API timeout: {ex.Message}");
            return "Error: Claude API request timed out";
        }
        catch (JsonException ex)
        {
            Console.Error.WriteLine($"JSON parsing error: {ex.Message}");
            return "Error: Invalid response from Claude API";
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Unexpected error in Claude service: {ex.Message}");
            return "Error: Internal error in Claude service";
        }
    }
}
