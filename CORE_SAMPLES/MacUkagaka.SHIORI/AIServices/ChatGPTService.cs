using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace MacUkagaka.SHIORI.AIServices;

public class ChatGPTService : IAIService
{
    private readonly string _apiKey;
    private readonly string _model;

    public ChatGPTService(string apiKey, string model)
    {
        _apiKey = apiKey;
        _model = string.IsNullOrEmpty(model) ? "gpt-3.5-turbo" : model;
    }

    public async Task<string> GenerateResponseAsync(string prompt)
    {
        try
        {
            if (string.IsNullOrEmpty(_apiKey))
                return "Error: ChatGPT API key not configured";
                
            if (string.IsNullOrEmpty(prompt))
                return "Error: Empty prompt";

            var endpoint = "https://api.openai.com/v1/chat/completions";
            var obj = new
            {
                model = _model,
                messages = new[] { new { role = "user", content = prompt } },
                max_tokens = 1024
            };
            var json = JsonSerializer.Serialize(obj);
            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
            request.Headers.Add("Authorization", $"Bearer {_apiKey}");
            request.Content = new StringContent(json, Encoding.UTF8, "application/json");
            
            using var client = new HttpClient();
            client.Timeout = TimeSpan.FromSeconds(30);
            
            var response = await client.SendAsync(request);
            var str = await response.Content.ReadAsStringAsync();
            
            if (!response.IsSuccessStatusCode)
            {
                Console.Error.WriteLine($"ChatGPT API error: {response.StatusCode} - {str}");
                return $"Error: ChatGPT API returned {response.StatusCode}";
            }
            
            using var doc = JsonDocument.Parse(str);
            if (doc.RootElement.TryGetProperty("choices", out var choices) && choices.GetArrayLength() > 0)
            {
                var firstChoice = choices[0];
                if (firstChoice.TryGetProperty("message", out var message) &&
                    message.TryGetProperty("content", out var content))
                {
                    return content.GetString() ?? "Error: Empty response from ChatGPT";
                }
            }
            
            Console.Error.WriteLine($"Unexpected ChatGPT response format: {str}");
            return "Error: Unexpected response format from ChatGPT";
        }
        catch (HttpRequestException ex)
        {
            Console.Error.WriteLine($"Network error calling ChatGPT API: {ex.Message}");
            return "Error: Network problem connecting to ChatGPT";
        }
        catch (TaskCanceledException ex)
        {
            Console.Error.WriteLine($"ChatGPT API timeout: {ex.Message}");
            return "Error: ChatGPT API request timed out";
        }
        catch (JsonException ex)
        {
            Console.Error.WriteLine($"JSON parsing error: {ex.Message}");
            return "Error: Invalid response from ChatGPT API";
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Unexpected error in ChatGPT service: {ex.Message}");
            return "Error: Internal error in ChatGPT service";
        }
    }
}
