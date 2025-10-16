namespace MacUkagaka.SHIORI.AIServices;

public interface IAIService
{
    Task<string> GenerateResponseAsync(string prompt);
}
