using System.Text;
using MacUkagaka.SHIORI.AIServices;
using MacUkagaka.SHIORI.Models;
using MacUkagaka.SHIORI.Utils;

namespace MacUkagaka.SHIORI;

class Program
{
    static async Task Main(string[] args)
    {
        try
        {
            await File.WriteAllTextAsync("/tmp/shiori_startup.log", $"SHIORI started at {DateTime.Now}\n");
            await File.AppendAllTextAsync("/tmp/shiori_startup.log", $"Args: {string.Join(", ", args)}\n");
            await File.AppendAllTextAsync("/tmp/shiori_startup.log", $"Working directory: {Environment.CurrentDirectory}\n");
        var configPath = args.Length > 0 ? args[0] : "config.json";
        var config = new ConfigManager(configPath);
        IAIService service = config.DefaultService switch
        {
            "claude" => new ClaudeService(config.GetApiKey("claude") ?? string.Empty, config.GetModel("claude") ?? string.Empty),
            "gemini" => new GeminiService(config.GetApiKey("gemini") ?? string.Empty, config.GetModel("gemini") ?? string.Empty),
            _ => new ChatGPTService(config.GetApiKey("chatgpt") ?? string.Empty, config.GetModel("chatgpt") ?? string.Empty)
        };

        while (true)
        {
            var requestText = ReadRequest();
            if (requestText == null) break;

            var request = SHIORIRequest.Parse(requestText);
            string value = string.Empty;
            if (request.Id == "Version")
            {
                value = "MacUkagaka.SHIORI 1.0.0";
            }
            else if (request.Id == "OnBoot")
            {
                value = SakuraScriptBuilder.Simple("こんにちは！MacUkagakaです。");
            }
            else if (request.Id == "OnClose")
            {
                value = SakuraScriptBuilder.Simple("さようなら！");
            }
            else if (request.Id == "OnSecondChange")
            {
                Console.Write(new SHIORIResponse { Value = string.Empty }.ToString());
                continue;
            }
            else if (request.Id == "OnMouseClick")
            {
                var surfaceId = request.GetReference(0) ?? "0";
                var x = request.GetReference(1) ?? "0";
                var y = request.GetReference(2) ?? "0";
                var button = request.GetReference(3) ?? "0";
                
                value = SakuraScriptBuilder.Simple($"クリックありがとう！座標({x}, {y})をクリックしました。");
            }
            else if (request.Id == "OnTalk")
            {
                var prompt = request.GetReference(0) ?? string.Empty;
                value = SakuraScriptBuilder.Simple(await service.GenerateResponseAsync(prompt));
            }

            var response = new SHIORIResponse { Value = value };
            Console.Write(response.ToString());
        }
        }
        catch (Exception ex)
        {
            try
            {
                await File.AppendAllTextAsync("/tmp/shiori_startup.log", $"ERROR: {ex}\n");
            }
            catch { }
            throw;
        }
    }

    static string? ReadRequest()
    {
        var sb = new StringBuilder();
        string? line;
        while ((line = Console.ReadLine()) != null)
        {
            sb.AppendLine(line);
            if (string.IsNullOrWhiteSpace(line))
                break;
        }
        if (sb.Length == 0)
            return null;
        return sb.ToString();
    }
}
