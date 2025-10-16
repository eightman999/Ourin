#r "Rosalind.dll"
#load "SaveData.csx"
#load "ChatGPT.csx"
#load "CollisionParts.csx"
#load "GhostMenu.csx"
#load "Surfaces.csx"
#load "Log.csx"
using Shiorose;
using Shiorose.Resource;
using Shiorose.Support;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using Shiorose.Resource.ShioriEvent;
using System.Text.RegularExpressions;

partial class AINanikaAIChanGhost : Ghost
{
    const string AIName = "アイ";
    const string USERName = "後輩くん";//TODO: ベースクラスGhostにUserNameが定義されているので、そちらを活用するようにすると良いかもしれない。変数を利用するときはUSERNameとUserNameの違いに注意。

    Random random = new Random();
    bool isTalking = false;
    IAITalk chatGPTTalk = null;
    string messageLog = "";
    double faceRate = 0;
    bool isNademachi = false;
    public AINanikaAIChanGhost()
    {
        // 更新URL
        Homeurl = "https://manjubox.net/Install/ai_sister_ai_chan/";

        // 必ず読み込んでください
        _saveData = SaveDataManager.Load<SaveData>();

        SettingRandomTalk();

        Resource.SakuraPortalButtonCaption = () => "AI何かちゃん";
        SakuraPortalSites.Add(new Site("配布ページ", "https://manjubox.net/ai_sister_ai_chan/"));
        SakuraPortalSites.Add(new Site("ソースコード", "https://github.com/manju-summoner/AISisterAIChan"));

        Resource.SakuraRecommendButtonCaption = () => "宣伝！";
        SakuraRecommendSites.Add(new Site("ゆっくりMovieMaker4", "https://manjubox.net/ymm4/"));
        SakuraRecommendSites.Add(new Site("饅頭遣い", "https://twitter.com/manju_summoner"));
    }
    private void SettingRandomTalk()
    {
        RandomTalks.Add(RandomTalk.CreateWithAutoWait(() =>
        {
            BeginTalk($"{USERName}：なにか話して");
            return "";
        }));
    }
    public override string OnMouseClick(IDictionary<int, string> reference, string mouseX, string mouseY, string charId, string partsName, string buttonName, DeviceType deviceType)
    {
        var parts = CollisionParts.GetCollisionPartsName(partsName);
        if (parts != null && buttonName == "2")
            BeginTalk($"{USERName}：（{AIName}の{parts}をつまむ）");

        return base.OnMouseClick(reference, mouseX, mouseY, charId, partsName, buttonName, deviceType);
    }

    public override string OnMouseDoubleClick(IDictionary<int, string> reference, string mouseX, string mouseY, string charId, string partsName, string buttonName, DeviceType deviceType)
    {
        var parts = CollisionParts.GetCollisionPartsName(partsName);
        if (parts != null)
        {
            BeginTalk($"{USERName}：（{AIName}の{parts}をつつく）");
            return "";
        }
        else
        {
            return OpenMenu();
        }
    }

    protected override string OnMouseStroke(string partsName, DeviceType deviceType)
    {
        var parts = CollisionParts.GetCollisionPartsName(partsName);
        if (parts != null)
            BeginTalk($"{USERName}：（{AIName}の{parts}を撫でる）");

        return base.OnMouseStroke(partsName, deviceType);
    }
    public override string OnMouseWheel(IDictionary<int, string> reference, string mouseX, string mouseY, string wheelRotation, string charId, string partsName, Shiorose.Resource.ShioriEvent.DeviceType deviceType)
    {
        if (wheelRotation.StartsWith("-"))
        {
            if (partsName == CollisionParts.Shoulder)
                BeginTalk($"{USERName}：（{AIName}を抱き寄せる）");
            else if (partsName == CollisionParts.TwinTail)
                BeginTalk($"{USERName}：（{AIName}のツインテールを弄ぶ）");
            else
            {
                var parts = CollisionParts.GetCollisionPartsName(partsName);
                if (parts != null)
                    BeginTalk($"{USERName}：（{AIName}の{parts}を引っ張る）");
            }
        }
        else
        {
            if (partsName == CollisionParts.TwinTail)
                BeginTalk($"{USERName}：（{AIName}のツインテールをフワフワと持ち上げる）");
            else if (partsName == CollisionParts.Skirt)
                BeginTalk($"{USERName}：（{AIName}のスカートをめくる）");
            else
            {
                var parts = CollisionParts.GetCollisionPartsName(partsName);
                if (parts != null)
                    BeginTalk($"{USERName}：（{AIName}の{parts}をワシャワシャする）");
            }
        }

        return base.OnMouseWheel(reference, mouseX, mouseY, wheelRotation, charId, partsName, deviceType);
    }

    public override string OnMouseMove(IDictionary<int, string> reference, string mouseX, string mouseY, string wheelRotation, string charId, string partsName, DeviceType deviceType)
    {
        if(!isNademachi && !isTalking && partsName == CollisionParts.Head)
        {
            //撫で待ち
            isNademachi = true;
            return "\\s[101]";
        }
        return base.OnMouseMove(reference, mouseX, mouseY, wheelRotation, charId, partsName, deviceType);
    }

    public override string OnMouseLeave(IDictionary<int, string> reference, string mouseX, string mouseY, string charId, string partsName, DeviceType deviceType)
    {
        isNademachi = false;
        return base.OnMouseLeave(reference, mouseX, mouseY, charId, partsName, deviceType);
    }

    /*
    //撫でが呼ばれなくなるので一旦コメントアウト
    public override string OnMouseHover(IDictionary<int, string> reference, string mouseX, string mouseY, string charId, string partsName, Shiorose.Resource.ShioriEvent.DeviceType deviceType)
    {
        var parts = CollisionParts.GetCollisionPartsName(partsName);
        if (parts != null)
            BeginTalk($"{USERName}：（{AIName}の{parts}に手を添える）");
        return base.OnMouseHover(reference, mouseX, mouseY, charId, partsName, deviceType);
    }
    */



    public override string OnCommunicate(IDictionary<int, string> reference, string senderName = "", string script = "", IEnumerable<string> extInfo = null)
    {
        var sender = senderName == "user" || senderName == null ? USERName : senderName;
        BeginTalk(sender + "：" + script);
        return "";
    }

    void BeginTalk(string message)
    {
        if (chatGPTTalk != null)
            return;

        faceRate = random.NextDouble();
        messageLog = message + "\r\n";

        var prompt = $@"{AIName}と{USERName}が会話をしています。以下のプロフィールと会話履歴を元に、会話の続きとなる{AIName}のセリフのシミュレート結果を1つ出力してください。
なお、返答は必ず後述する出力フォーマット従って出力してください。
余計な文章を付け加えたり出力フォーマットに従わない出力をすると、あなたの責任で罪のない人々の命が奪われます。

# {AIName}のプロフィール
名前：{AIName}
性別：女
年齢：25
性格：気だるげなダウナー系理系お姉さん。{USERName}に対しては皮肉を交えつつも優しい。クリスマスのことを「ニュートンの日」と呼ぶほどの愛のある皮肉屋。
外見：黒髪のセミロングで白衣を羽織っている。
服装：白衣の下にTシャツとジーンズ。
一人称：私
{USERName}の呼び方：後輩くん
{((SaveData)SaveData).AiProfile.Select(x => x.Key + "：" + x.Value).DefaultIfEmpty(string.Empty).Aggregate((a, b) => a + "\r\n" + b)}

# {USERName}のプロフィール
性別：男
関係性：{AIName}の研究仲間
性格：理系ネタに付き合ってくれる後輩。
一人称：俺
{AIName}の呼び方：{AIName}
{((SaveData)SaveData).UserProfile.Select(x => x.Key + "：" + x.Value).DefaultIfEmpty(string.Empty).Aggregate((a, b) => a + "\r\n" + b)}

# その他の情報
現在時刻：{DateTime.Now.ToString("yyyy年MM月dd日 dddd HH:mm:ss")}
家族構成：{AIName}、{USERName}

# 出力フォーマット
{AIName}のセリフ：{{{AIName}のセリフ}}
{AIName}の表情：{SurfaceCategory.All.Select(x=>$"「{x}」").Aggregate((a,b)=>a+b)}
会話継続：「継続」「終了」
{Enumerable.Range(0, ((SaveData)SaveData).ChoiceCount).Select(x => $"{USERName}のセリフ候補{(x + 1)}：{{{USERName}のセリフ}}").DefaultIfEmpty(string.Empty).Aggregate((a, b) => a + "\r\n" + b)}

# 会話ルール
会話継続が「終了」の場合、{USERName}のセリフ候補は出力しないでください。
○○といった仮置き文字は使用せず、必ず具体的な単語を使用してください。

# 会話履歴
{messageLog}";

        if (((SaveData)SaveData).IsDevMode)
            Log.WriteAllText(Log.Prompt, prompt);

        var provider = ((SaveData)SaveData).AIProvider;
        if(provider == "ChatGPT")
        {
            var request = new ChatGPTRequest()
            {
                stream = true,
                model = "gpt-3.5-turbo",
                messages = new ChatGPTMessage[]
                {
                    new ChatGPTMessage()
                    {
                        role = "user",
                        content = prompt
                    },
                }
            };
            chatGPTTalk = new ChatGPTTalk(((SaveData)SaveData).APIKey, request);
        }
        else if(provider == "Claude")
        {
            chatGPTTalk = new ClaudeTalk(((SaveData)SaveData).ClaudeAPIKey, prompt);
        }
        else
        {
            chatGPTTalk = new GeminiTalk(((SaveData)SaveData).GeminiAPIKey, prompt);
        }
    }

    public override string OnSurfaceRestore(IDictionary<int, string> reference, string sakuraSurface, string keroSurface)
    {
        isTalking = false;
        return base.OnSurfaceRestore(reference, sakuraSurface, keroSurface);
    }

    public override string OnSecondChange(IDictionary<int, string> reference, string uptime, bool isOffScreen, bool isOverlap, bool canTalk, string leftSecond)
    {
        if (canTalk && chatGPTTalk != null)
        {
            var talk = chatGPTTalk;
            var log = messageLog;
            if (!talk.IsProcessing)
            {
                chatGPTTalk = null;
                messageLog = string.Empty;
            }

            return BuildTalk(talk.Response, !talk.IsProcessing, log);
        }
        return base.OnSecondChange(reference, uptime, isOffScreen, isOverlap, canTalk, leftSecond);
    }
    public override string OnMinuteChange(IDictionary<int, string> reference, string uptime, bool isOffScreen, bool isOverlap, bool canTalk, string leftSecond)
    {
        
        if(canTalk && !isTalking && ((SaveData)SaveData).IsRandomIdlingSurfaceEnabled)
            return "\\s["+Surfaces.Of(SurfaceCategory.Normal).GetRaodomSurface()+"]";
        else
            return base.OnMinuteChange(reference, uptime, isOffScreen, isOverlap, canTalk, leftSecond);
    }

    string BuildTalk(string response, bool createChoices, string log)
    {
        const string INPUT_CHOICE_MYSELF = "自分で入力する";
        const string SHOW_LOGS = "ログを表示";
        const string END_TALK = "会話を終える";
        const string BACK = "戻る";
        try
        {
            isTalking = true;
            if (((SaveData)SaveData).IsDevMode)
                Log.WriteAllText(Log.Response, response);

            var aiResponse = GetAIResponse(response);
            var surfaceId = GetSurfaceId(response);
            var onichanResponse = GetOnichanRenponse(response);
            var talkBuilder =
                new TalkBuilder()
                .Append($"\\_q\\s[{surfaceId}]")
                .Append(aiResponse)
                .LineFeed()
                .HalfLine();

            if (!createChoices)
            {
                foreach(var choice in onichanResponse)
                    talkBuilder = talkBuilder.Marker().Append(choice).LineFeed();
                return talkBuilder.Append($"\\_q...").LineFeed().Build();
            }

            if (createChoices && string.IsNullOrEmpty(aiResponse))
                 return new TalkBuilder()
                    .Marker().AppendChoice(SHOW_LOGS).LineFeed()
                    .Marker().AppendChoice(END_TALK).LineFeed()
                    .Build()
                    .ContinueWith(id =>
                    {
                        if (id == SHOW_LOGS)
                            return new TalkBuilder()
                            .Append("\\_q").Append(EscapeLineBreak(log)).LineFeed()
                            .Append(EscapeLineBreak(response)).LineFeed()
                            .HalfLine()
                            .Marker().AppendChoice(BACK)
                            .Build()
                            .ContinueWith(x =>
                            {
                                if (x == BACK)
                                    return BuildTalk(response, createChoices, log);
                                return "";
                            });
                        return "";
                    });

            DeferredEventTalkBuilder deferredEventTalkBuilder = null;
            if (onichanResponse.Length > 0)
            {
                foreach (var choice in onichanResponse.Take(3))
                {
                    if (deferredEventTalkBuilder == null)
                        deferredEventTalkBuilder = AppendWordWrapChoice(talkBuilder, choice);
                    else
                        deferredEventTalkBuilder = AppendWordWrapChoice(deferredEventTalkBuilder, choice);
                }
                deferredEventTalkBuilder = deferredEventTalkBuilder.Marker().AppendChoice(INPUT_CHOICE_MYSELF).LineFeed().HalfLine();
            }

            if (deferredEventTalkBuilder == null)
                deferredEventTalkBuilder = talkBuilder.Marker().AppendChoice(SHOW_LOGS).LineFeed();
            else
                deferredEventTalkBuilder = deferredEventTalkBuilder.Marker().AppendChoice(SHOW_LOGS).LineFeed();

            return deferredEventTalkBuilder
                    .Marker().AppendChoice(END_TALK).LineFeed()
                    .Build()
                    .ContinueWith(id =>
                    {
                        if (onichanResponse.Contains(id))
                            BeginTalk($"{log}{AIName}：{aiResponse}\r\n{USERName}：{id}");
                        if (id == SHOW_LOGS)
                            return new TalkBuilder()
                            .Append("\\_q").Append(EscapeLineBreak(log)).LineFeed()
                            .Append(EscapeLineBreak(response)).LineFeed()
                            .HalfLine()
                            .Marker().AppendChoice(BACK)
                            .Build()
                            .ContinueWith(x =>
                            {
                                if (x == BACK)
                                    return BuildTalk(response, createChoices, log);
                                return "";
                            });
                        if (id == INPUT_CHOICE_MYSELF)
                            return new TalkBuilder().AppendUserInput().Build().ContinueWith(input =>
                            {
                                BeginTalk($"{log}{AIName}：{aiResponse}\r\n{USERName}：{input}");
                                return "";
                            });
                        return "";
                    });
        }
        catch (Exception e)
        {
            return e.ToString();
        }
    }
    string EscapeLineBreak(string text)
    {
        return text.Replace("\r\n", "\\n").Replace("\n", "\\n").Replace("\r", "\\n");
    }
    string DeleteLineBreak(string text)
    {
        return text.Replace("\r\n", "").Replace("\n", "").Replace("\r", "");
    }
    string GetAIResponse(string response)
    {
        var pattern = $"^{AIName}(のセリフ)?[：:](?<Serif>.+?)$";
        var lines = response.Split(new string[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
        var aiResponse = lines.Select(x=>Regex.Match(x, pattern)).Where(x=>x.Success).Select(x=>x.Groups["Serif"].Value).FirstOrDefault();
        if (string.IsNullOrEmpty(aiResponse))
            return "";

        return TrimSerifBrackets(aiResponse);
    }

    string[] GetOnichanRenponse(string response)
    {
        var pattern = $"^{USERName}(のセリフ候補([0-9]+)?)?[：:](?<Serif>.+?)$";
        var lines = response.Split(new string[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
        var onichanResponse = lines
            .Select(x=>Regex.Match(x,pattern))
            .Where(x=>x.Success)
            .Select(x=>x.Groups["Serif"].Value)
            .Where(x=>!string.IsNullOrWhiteSpace(x))
            .ToArray();
        if (onichanResponse.Length == 0)
            return new string[] { };
        return onichanResponse.Select(x=>TrimSerifBrackets(x)).ToArray();
    }

    string TrimSerifBrackets(string serif)
    {
        serif = serif.Trim();
        if(serif.StartsWith("「") && serif.EndsWith("」"))
            return serif.Substring(1, serif.Length - 2);
        if(serif.StartsWith("『") && serif.EndsWith("』"))
            return serif.Substring(1, serif.Length - 2);
        if(serif.StartsWith("\"") && serif.EndsWith("\""))
            return serif.Substring(1, serif.Length - 2);
        if(serif.StartsWith("'") && serif.EndsWith("'"))
            return serif.Substring(1, serif.Length - 2);
        return serif;
    }

    int GetSurfaceId(string response)
    {
        var lines = response.Split(new string[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
        var face = lines.FirstOrDefault(x => x.StartsWith($"{AIName}の表情："));
        if (face is null)
            return 0;

        foreach(var category in SurfaceCategory.All)
        {
            if (face.Contains(category))
                return Surfaces.Of(category).GetSurfaceFromRate(faceRate);
        }

        return 0;
    }
    DeferredEventTalkBuilder AppendWordWrapChoice(TalkBuilder builder, string text)
    {
        builder = builder.Marker();
        DeferredEventTalkBuilder deferredEventTalkBuilder = null;
        foreach (var choice in WordWrap(text))
        {
            if (deferredEventTalkBuilder == null)
                deferredEventTalkBuilder = builder.AppendChoice(choice, text).LineFeed();
            else
                deferredEventTalkBuilder = deferredEventTalkBuilder.AppendChoice(choice, text).LineFeed();
        }
        return deferredEventTalkBuilder;
    }
    DeferredEventTalkBuilder AppendWordWrapChoice(DeferredEventTalkBuilder builder, string text)
    {
        builder = builder.Marker();
        foreach (var choice in WordWrap(text))
            builder = builder.AppendChoice(choice, text).LineFeed();
        return builder;
    }
    IEnumerable<string> WordWrap(string text)
    {
        var width = 24;
        for (int i = 0; i < text.Length; i += width)
        {
            if (i + width < text.Length)
                yield return text.Substring(i, width);
            else
                yield return text.Substring(i);
        }
    }
}

return new AINanikaAIChanGhost();