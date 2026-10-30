#r "@ROSALIND_PRODUCTS@/Rosalind.dll"
#r "@ROSALIND_PRODUCTS@/Newtonsoft.Json.dll"
using System;
using System.Collections.Generic;
using Shiorose;
using Shiorose.Resource;
using Shiorose.Resource.ShioriEvent;
public class ProbeSave : BaseSaveData { public int Boots { get; set; } }
public class ProbeGhost : Ghost {
 public ProbeGhost() { _saveData = SaveDataManager.Load<ProbeSave>(); }
 public override string OnBoot(IDictionary<int,string> reference, string shellName = "", bool isHalt=false, string haltGhostName="") {
  var data = (ProbeSave)SaveData; data.Boots++; return "桜鈴 🌸 " + data.Boots;
 }
 public override string OnClose(IDictionary<int,string> reference,string reason="") { return "終了します。"; }
 public override string OnMouseDoubleClick(IDictionary<int,string> reference,string x,string y,string character,string parts,string button,DeviceType device) { return reference[0]; }
}
return new ProbeGhost();
