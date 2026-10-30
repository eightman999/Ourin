// Self-authored UTF-8 dictionary for the explicit CP932 wire bridge.
int boots = 0;
string remembered;
bool load(string path) {
    file f;
    if (f.open("savedata.bin", "r") >= 0) {
        boots = int(f.readInt(4));
        remembered = f.readString(1024);
        f.close();
    }
    if (f.open("loaded-path.txt", "w") < 0) return false;
    f.writeString(path); f.close();
    return true;
}
bool unload() {
    file f;
    if (f.open("savedata.bin", "w") < 0) return false;
    f.writeInt(boots, 4); f.writeString(remembered);
    return f.close() >= 0;
}
string request(string wire) {
    dictionary headers;
    array<string>@ lines = wire.split("\r\n");
    for (uint i = 0; i < lines.length(); i++) {
        int colon = lines[i].findFirst(": ");
        if (colon >= 0) headers.set(lines[i].substr(0, colon), lines[i].substr(colon + 2));
    }
    string id, value;
    headers.get("ID", id);
    if (wire.substr(0, 7) == "NOTIFY ") { headers.get("Reference0", remembered); return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"; }
    if (id == "version") value = "dktrtk/AngelScript-CP932";
    else if (id == "OnBoot") value = "桜鈴 表ソ " + (++boots);
    else if (id == "OnEcho") { headers.get("Reference0", value); remembered = value; }
    else if (id == "OnRemembered") value = remembered;
    else if (id == "OnEmoji") value = "🌸";
    else if (id == "OnClose") value = "終了します。";
    else return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n";
    return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: " + value + "\r\n\r\n";
}
