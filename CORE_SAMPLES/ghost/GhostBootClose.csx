#r "Rosalind.dll"
#load "SaveData.csx"
using Shiorose;
using Shiorose.Resource;
using Shiorose.Support;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

partial class AINanikaAIChanGhost : Ghost
{
    public override string OnBoot(IDictionary<int, string> references, string shellName = "", bool isHalt = false, string haltGhostName = "")
    {
        return new TalkBuilder()
        .AppendLine("おかえり、後輩くん。")
        .BuildWithAutoWait();
    }

    public override string OnFirstBoot(IDictionary<int, string> reference, int vanishCount = 0)
    {
        return new TalkBuilder()
        .AppendLine("おかえり、後輩くん。")
        .BuildWithAutoWait();
    }

    public override string OnClose(IDictionary<int, string> reference, string reason = "")
    {
        return 
        new TalkBuilder()
        .Append("また話そうね、後輩くん。")
        .EmbedValue("\\-")
        .BuildWithAutoWait();
    }
}