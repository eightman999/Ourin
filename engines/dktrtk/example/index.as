// Self-authored dictionary executed unchanged by both SDK build variants.
class Box { int number = 7; }
int boots = 0;
bool load(string path) {
    file f;
    if (f.open("savedata.bin", "r") >= 0) {
        boots = int(f.readInt(4));
        f.close();
    }
    if (f.open("loaded-path.txt", "w") < 0) return false;
    f.writeString(path);
    f.close();
    return true;
}
bool unload() {
    file f;
    if (f.open("savedata.bin", "w") < 0) return false;
    f.writeInt(boots, 4);
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
    if (wire.substr(0, 7) == "NOTIFY ") return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n";
    if (id == "version") value = "dktrtk/AngelScript";
    else if (id == "OnBoot") value = "桜鈴 🌸 " + (++boots);
    else if (id == "OnEcho") headers.get("Reference0", value);
    else if (id == "OnMath") {
        grid<int> cells(2, 2);
        cells[1, 1] = int(sqrt(81.0));
        value = "計算 " + cells[1, 1];
    }
    else if (id == "OnFilesystem") {
        filesystem fs;
        array<string>@ files = fs.getFiles();
        if (files.find("loaded-path.txt") < 0 || fs.isDir("loaded-path.txt") || fs.getCurrentPath().length() == 0)
            value = "filesystem failure";
        else value = "filesystem OK";
    }
    else if (id == "OnAddons") {
        any stored;
        int64 original = 7, recovered = 0;
        stored.store(original);
        Box@ object = Box();
        weakref<Box> weak(object);
        ref@ handle = @object;
        Box@ restored = cast<Box>(handle);
        complex z(3, 4);
        array<int> numbers = {3, 1};
        numbers.insertAt(1, 2); numbers.sortAsc();
        // Legacy SDK registered methods and property accessors simultaneously.
        array<int> legacy; legacy.length = 2;
        string text = "abc"; text.length = 2;
        dictionary d; d.set("x", 1); d.delete("x");
        if (stored.retrieve(recovered) && recovered == 7 && weak.get() is object && restored.number == 7 &&
            legacy.length == 2 && legacy.length() == 2 && text.length == 2 && text.length() == 2 &&
            int(z.abs()) == 5 && numbers[0] == 1 && numbers[1] == 2 && numbers[2] == 3 && !d.exists("x"))
            value = "addons OK";
        else value = "addons failure";
    }
    else if (id == "OnClose") value = "終了します。";
    else return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n";
    return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: " + value + "\r\n\r\n";
}
