# Self-authored integration example using the real pinned shioridll module.
import shioridll
import std/[os, strutils]

var directory: string
shioriLoadCallback = proc(path: string): bool =
  directory = path
  writeFile(directory / "nim-loaded.path", path)
  true

shioriRequestCallback = proc(wire: string): string =
  var id = ""
  var reference = ""
  for line in wire.splitLines():
    if line.startsWith("ID: "): id = line[4..^1]
    if line.startsWith("Reference0: "): reference = line[12..^1]
  if wire.startsWith("NOTIFY "):
    return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"
  var value: string
  case id
  of "version": value = "0.0.1"
  of "name": value = "Ourin Nim integration example"
  of "OnBoot": value = "\\0\\s[0]こんにちは、桜鈴。\\e"
  of "OnEcho": value = reference
  of "OnClose": value = "\\0終了します。\\-"
  else:
    return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"
  "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nSender: nimshiori\r\nValue: " & value & "\r\n\r\n"

shioriUnloadCallback = proc(): bool =
  writeFile(directory / "nim-unloaded.marker", "unloaded")
  true
