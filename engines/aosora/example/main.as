// Self-authored regression fixture executed by the actual Aosora interpreter.
function OnAosoraDefaultSaveData { Save.Data.Value = "未保存"; }
function OnBoot { return "\0蒼空・桜鈴起動\e"; }
function OnEcho { return Shiori.Reference[0]; }
function OnSet { Save.Data.Value = Shiori.Reference[0]; return "saved"; }
function OnRead { return Save.Data.Value; }
function OnClose { return "蒼空終了"; }
