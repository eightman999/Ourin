#r "Rosalind.dll"
#load "SaveData.csx"
using Shiorose;
using Shiorose.Resource;
using Shiorose.Resource.ShioriEvent;
using Shiorose.Support;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

partial class AINanikaAIChanGhost : Ghost
{

    private string OpenMenu()
    {
        var provider = ((SaveData)SaveData).AIProvider;
        var save = (SaveData)SaveData;
        if((provider == "ChatGPT" && string.IsNullOrEmpty(save.APIKey)) ||
           (provider == "Claude" && string.IsNullOrEmpty(save.ClaudeAPIKey)) ||
           (provider == "Gemini" && string.IsNullOrEmpty(save.GeminiAPIKey)))
            return ChangeAPITalk();

        const string RAND = "なにか話して";
        const string COMMUNICATE = "話しかける";
        const string CHANGEPROFILE = "プロフィールを変更する";
        const string SETTINGS = "設定を変えたい";
        const string CANCEL = "なんでもない";

        return new TalkBuilder().Append("どうしたの？").LineFeed()
                                .HalfLine()
                                .Marker().AppendChoice(RAND).LineFeed()
                                .Marker().AppendChoice(COMMUNICATE).LineFeed()
                                .HalfLine()
                                .Marker().AppendChoice(CHANGEPROFILE).LineFeed()
                                .Marker().AppendChoice(SETTINGS).LineFeed()
                                .HalfLine()
                                .Marker().AppendChoice(CANCEL)
                                .BuildWithAutoWait()
                                .ContinueWith((id) =>
                                {
                                    switch (id)
                                    {
                                        case RAND:
                                            return OnRandomTalk();
                                        case COMMUNICATE:
                                            return new TalkBuilder().Append("なになに？").AppendCommunicate().Build();
                                        case CHANGEPROFILE:
                                            return ChangeProfileTalk();
                                        case SETTINGS:
                                            return SettingsTalk();
                                        default:
                                            return new TalkBuilder().Append("そう…？").BuildWithAutoWait();
                                    }
                                });
    }

    private string SettingsTalk(){
        const string CHANGE_API_SETTING = "AIサービスの設定を変更する";
        const string CHANGE_RANDOMTALK_INTERVAL = "ランダムトークの頻度を変更する";
        const string CHANGE_CHOICE_COUNT = "選択肢の数を変更する";
        string CHANGE_RANDOM_IDLING_SURFACE = "定期的に身じろぎする（現在："+(((SaveData)SaveData).IsRandomIdlingSurfaceEnabled ? "有効" : "無効")+"）";
        string CHANGE_DEVMODE = "開発者モードを変更する（現在："+(((SaveData)SaveData).IsDevMode ? "有効" : "無効")+"）";
        const string BAKC = "戻る";
        return new TalkBuilder()
        .Append("設定を変更するね。")
        .LineFeed()
        .HalfLine()
        .Marker().AppendChoice(CHANGE_API_SETTING).LineFeed()
        .HalfLine()
        .Marker().AppendChoice(CHANGE_RANDOMTALK_INTERVAL).LineFeed()
        .Marker().AppendChoice(CHANGE_CHOICE_COUNT).LineFeed()
        .Marker().AppendChoice(CHANGE_RANDOM_IDLING_SURFACE).LineFeed()
        .HalfLine()
        .Marker().AppendChoice(CHANGE_DEVMODE).LineFeed()
        .HalfLine()
        .Marker().AppendChoice(BAKC)
        .BuildWithAutoWait()
        .ContinueWith(id=>
        {
            if (id == CHANGE_API_SETTING)
                return ChangeAPITalk();
            else if (id == CHANGE_RANDOMTALK_INTERVAL)
                return ChangeRandomTalkIntervalTalk();
            else if (id == CHANGE_CHOICE_COUNT)
                return ChangeChoiceCountTalk();
            else if (id == CHANGE_RANDOM_IDLING_SURFACE)
            {
                ((SaveData)SaveData).IsRandomIdlingSurfaceEnabled = !((SaveData)SaveData).IsRandomIdlingSurfaceEnabled;
                return SettingsTalk();
            }
            else if (id == CHANGE_DEVMODE)
            {
                ((SaveData)SaveData).IsDevMode = !((SaveData)SaveData).IsDevMode;
                return SettingsTalk();
            }
            else
                return OpenMenu();
        });
    }

    private string ChangeAPIKeyTalk(string provider){
        var save = (SaveData)SaveData;
        string defValue = provider == "ChatGPT" ? save.APIKey : provider == "Claude" ? save.ClaudeAPIKey : save.GeminiAPIKey;
        return new TalkBuilder().Append($"{provider}のAPIキーを入力してくれ、後輩くん。")
                                .AppendPassInput(defValue:defValue)
                                .Build()
                                .ContinueWith(apiKey=>
                                {
                                    if(provider == "ChatGPT") save.APIKey = apiKey;
                                    else if(provider == "Claude") save.ClaudeAPIKey = apiKey;
                                    else if(provider == "Gemini") save.GeminiAPIKey = apiKey;
                                    return new TalkBuilder().Append("設定が終わったよ、後輩くん。").BuildWithAutoWait();
                                });
    }

    private string ChangeProviderTalk(){
        const string GPT = "ChatGPT";
        const string CLAUDE = "Claude";
        const string GEMINI = "Gemini";
        const string BACK = "戻る";
        var current = ((SaveData)SaveData).AIProvider;
        return new TalkBuilder()
            .Append($"現在のAIは{current}だよ。どれを使う？").LineFeed()
            .HalfLine()
            .Marker().AppendChoice(GPT).LineFeed()
            .Marker().AppendChoice(CLAUDE).LineFeed()
            .Marker().AppendChoice(GEMINI).LineFeed()
            .HalfLine()
            .Marker().AppendChoice(BACK)
            .BuildWithAutoWait()
            .ContinueWith(id=>{
                if(id == BACK)
                    return ChangeAPITalk();
                ((SaveData)SaveData).AIProvider = id;
                return new TalkBuilder().Append("設定したよ、後輩くん。").BuildWithAutoWait();
            });
    }

    private string ChangeAPITalk(){
        const string PROVIDER = "利用するAIを選ぶ";
        const string KEY_GPT = "ChatGPTのAPIキー";
        const string KEY_CLAUDE = "ClaudeのAPIキー";
        const string KEY_GEMINI = "GeminiのAPIキー";
        const string BACK = "戻る";
        return new TalkBuilder()
            .Append("AIサービスの設定を変更するよ。").LineFeed()
            .HalfLine()
            .Marker().AppendChoice(PROVIDER).LineFeed()
            .Marker().AppendChoice(KEY_GPT).LineFeed()
            .Marker().AppendChoice(KEY_CLAUDE).LineFeed()
            .Marker().AppendChoice(KEY_GEMINI).LineFeed()
            .HalfLine()
            .Marker().AppendChoice(BACK)
            .BuildWithAutoWait()
            .ContinueWith(id=>{
                if(id == PROVIDER)
                    return ChangeProviderTalk();
                else if(id == KEY_GPT)
                    return ChangeAPIKeyTalk("ChatGPT");
                else if(id == KEY_CLAUDE)
                    return ChangeAPIKeyTalk("Claude");
                else if(id == KEY_GEMINI)
                    return ChangeAPIKeyTalk("Gemini");
                else
                    return SettingsTalk();
            });
    }

    private string ChangeRandomTalkIntervalTalk(){
        return new TalkBuilder().Append("ランダムトークの頻度を変更するよ。")
                                .LineFeed()
                                .HalfLine()
                                .Marker().AppendChoice("10秒").LineFeed()
                                .Marker().AppendChoice("30秒").LineFeed()
                                .Marker().AppendChoice("1分").LineFeed()
                                .Marker().AppendChoice("5分").LineFeed()
                                .Marker().AppendChoice("10分").LineFeed()
                                .Marker().AppendChoice("30分").LineFeed()
                                .Marker().AppendChoice("1時間").LineFeed()
                                .Marker().AppendChoice("なんでもない")
                                .BuildWithAutoWait()
                                .ContinueWith(id=>
                                {
                                    switch(id)
                                    {
                                        case "10秒":
                                            ((SaveData)SaveData).TalkInterval2 = 10;
                                            return new TalkBuilder().Append("10秒に1回話すね。").BuildWithAutoWait();
                                        case "30秒":
                                            ((SaveData)SaveData).TalkInterval = 30;
                                            return new TalkBuilder().Append("30秒に1回話すね。").BuildWithAutoWait();
                                        case "1分":
                                            ((SaveData)SaveData).TalkInterval = 60;
                                            return new TalkBuilder().Append("1分に1回話すね。").BuildWithAutoWait();
                                        case "5分":
                                            ((SaveData)SaveData).TalkInterval = 300;
                                            return new TalkBuilder().Append("5分に1回話すね。").BuildWithAutoWait();
                                        case "10分":
                                            ((SaveData)SaveData).TalkInterval = 600;
                                            return new TalkBuilder().Append("10分に1回話すね。").BuildWithAutoWait();
                                        case "30分":
                                            ((SaveData)SaveData).TalkInterval = 1800;
                                            return new TalkBuilder().Append("30分に1回話すね。").BuildWithAutoWait();
                                        case "1時間":
                                            ((SaveData)SaveData).TalkInterval = 3600;
                                            return new TalkBuilder().Append("1時間に1回話すね。").BuildWithAutoWait();
                                        default:
                                            return new TalkBuilder().Append("また何か変えたくなったら呼んでね。").BuildWithAutoWait();
                                    }
                                });
    }
    private string ChangeChoiceCountTalk(){
        return new TalkBuilder()
            .Append("会話時の選択肢の数を変更するよ。").LineFeed()
            .Append("……選択肢って何？").LineFeed().HalfLine()
            .Marker().AppendChoice("0個").LineFeed()
            .Marker().AppendChoice("1個").LineFeed()
            .Marker().AppendChoice("2個").LineFeed()
            .Marker().AppendChoice("3個").LineFeed()
            .Marker().AppendChoice("変更しない").LineFeed()
            .BuildWithAutoWait()
            .ContinueWith(id=>
            {
                switch(id){
                    case "0個":
                        ((SaveData)SaveData).ChoiceCount = 0;
                        return new TalkBuilder().Append("選択肢を表示しないようにするよ。").BuildWithAutoWait();
                    case "1個":
                        ((SaveData)SaveData).ChoiceCount = 1;
                        return new TalkBuilder().Append("選択肢を1個表示するよ。").BuildWithAutoWait();
                    case "2個":
                        ((SaveData)SaveData).ChoiceCount = 2;
                        return new TalkBuilder().Append("選択肢を2個表示するよ。").BuildWithAutoWait();
                    case "3個":
                        ((SaveData)SaveData).ChoiceCount = 3;
                        return new TalkBuilder().Append("選択肢を3個表示するよ。").BuildWithAutoWait();
                    default:
                        return new TalkBuilder().Append("また何か変えたくなったら呼んでね。").BuildWithAutoWait();
                }
            });
    }
    private string ChangeProfileTalk()
    {
        return new TalkBuilder().Append("どっちのプロフィールを変更する？").LineFeed()
                                .HalfLine()
                                .Marker().AppendChoice("アイ").LineFeed()
                                .Marker().AppendChoice("後輩くん").LineFeed()
                                .HalfLine()
                                .Marker().AppendChoice("戻る")
                                .Build()
                                .ContinueWith(id=>
                                {
                                    switch(id)
                                    {
                                        case "アイ":
                                            return ChangeProfileDictionaryTalk(((SaveData)SaveData).AiProfile, "私");
                                        case "後輩くん":
                                            return ChangeProfileDictionaryTalk(((SaveData)SaveData).UserProfile, "後輩くん");
                                        default:
                                            return OpenMenu();
                                    }
                                });
    }
    private string ChangeProfileDictionaryTalk(Dictionary<string,string> profile, string targetName)
    {
        try{
        DeferredEventTalkBuilder deferredEventTalkBuilder = null;
        var builder = new TalkBuilder()
            .Append("\\_q")
            .Append(targetName + "のプロフィールを変更するよ。").LineFeed()
            .HalfLine();
        
        foreach(var pair in profile)
        {
            if(deferredEventTalkBuilder == null)
                deferredEventTalkBuilder = builder.Marker().AppendChoice(pair.Key+"："+TrimLength(pair.Value,10), pair.Key).Marker().AppendChoice("削除","削除"+pair.Key).LineFeed();
            else
                deferredEventTalkBuilder = deferredEventTalkBuilder.Marker().AppendChoice(pair.Key+"："+TrimLength(pair.Value,10), pair.Key).Marker().AppendChoice("削除","削除"+pair.Key).LineFeed();
        }
        if(deferredEventTalkBuilder == null)
            deferredEventTalkBuilder = builder.Marker().AppendChoice("項目を追加する").LineFeed();
        else
            deferredEventTalkBuilder = deferredEventTalkBuilder.Marker().AppendChoice("項目を追加する").LineFeed();

        return deferredEventTalkBuilder
            .HalfLine()
            .Marker().AppendChoice("戻る").LineFeed()
            .BuildWithAutoWait()
            .ContinueWith(id=>
            {
                if(id == "戻る")
                    return ChangeProfileTalk();
                else if(id == "項目を追加する")
                    return AddProfileTalk(profile, id);
                else if(id.StartsWith("削除"))
                {
                    profile.Remove(id.Substring(2));
                    return ChangeProfileDictionaryTalk(profile, targetName);
                }
                else
                    return ChangeProfileDetailTalk(profile, id);
            });
        }catch(Exception e)
        {
            return e.ToString();
        }
    }
    private string ChangeProfileDetailTalk(Dictionary<string,string> profile, string key)
    {
        return new TalkBuilder().Append(key + "の内容を変更するよ。").LineFeed()
                                .HalfLine()
                                .AppendUserInput(defValue: profile.ContainsKey(key) ? profile[key] : "")
                                .Marker().AppendChoice("戻る").LineFeed()
                                .BuildWithAutoWait()
                                .ContinueWith(id=>
                                {
                                    if(id != "戻る")
                                        profile[key] = id;
                                    return ChangeProfileDictionaryTalk(profile, profile == ((SaveData)SaveData).AiProfile ? "私" : "後輩くん");
                                });
    }
    private string AddProfileTalk(Dictionary<string,string> profile, string targetName)
    {
        return new TalkBuilder().Append("追加する項目の名前を入力してね。").LineFeed()
                                .HalfLine()
                                .AppendUserInput()
                                .Marker().AppendChoice("戻る").LineFeed()
                                .BuildWithAutoWait()
                                .ContinueWith(id=>
                                {
                                    if(id != "戻る")
                                        return ChangeProfileDetailTalk(profile, id);
                                    else
                                        return ChangeProfileDictionaryTalk(profile, profile == ((SaveData)SaveData).AiProfile ? "アイ" : "後輩くん");
                                });
    }
    private string TrimLength(string text, int maxLength){
        if(text.Length > maxLength)
            return text.Substring(0, maxLength) + "…";
        else
            return text;
    }
}
