# Separate test dictionary, executed by upstream ModuleMain and IronPython 3.4.2.
# This is not a replacement for the unchanged upstream SHIORI 2.2 sample.
print("Kanahebi Python loaded: 桜鈴")
try:
    with open("boots.txt", "r", encoding="utf-8") as saved:
        boots = int(saved.read())
except IOError:
    boots = 0


def request(wire):
    global boots
    headers = {}
    for line in wire.split("\r\n"):
        if ": " in line:
            key, value = line.split(": ", 1)
            headers[key] = value
    event = headers.get("ID", "")
    value = None
    if not wire.startswith("NOTIFY "):
        if event == "version":
            value = "Kanahebi/IronPython-3.4.2"
        elif event == "OnBoot":
            boots += 1
            with open("boots.txt", "w", encoding="utf-8") as saved:
                saved.write(str(boots))
            value = "桜鈴 🌸 " + str(boots)
        elif event == "OnEcho":
            value = headers.get("Reference0", "")
        elif event == "OnClose":
            value = "終了します。"
    if value is None:
        return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"
    return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: " + value + "\r\n\r\n"
