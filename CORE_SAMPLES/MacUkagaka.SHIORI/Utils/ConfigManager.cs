using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace MacUkagaka.SHIORI.Utils;

public class ConfigManager
{
    private readonly JsonNode _root;

    public ConfigManager(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                // Create default config if file doesn't exist
                var defaultConfig = new
                {
                    ai_settings = new
                    {
                        default_service = "chatgpt",
                        chatgpt = new { api_key = "", model = "gpt-3.5-turbo" },
                        claude = new { api_key = "", model = "claude-3-haiku-20240307" },
                        gemini = new { api_key = "", model = "gemini-pro" }
                    }
                };
                var defaultJson = JsonSerializer.Serialize(defaultConfig, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(path, defaultJson);
            }
            
            var json = File.ReadAllText(path);
            _root = JsonNode.Parse(json) ?? new JsonObject();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Config error: {ex.Message}");
            _root = new JsonObject();
        }
    }

    public string DefaultService => _root["ai_settings"]?["default_service"]?.ToString() ?? "chatgpt";

    public string? GetApiKey(string service) => _root["ai_settings"]?[service]? ["api_key"]?.ToString();

    public string? GetModel(string service) => _root["ai_settings"]?[service]? ["model"]?.ToString();
}
