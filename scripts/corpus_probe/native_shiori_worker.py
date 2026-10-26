#!/usr/bin/env python3
"""Isolated JSON-line SHIORI worker with ABI-correct ctypes bindings (trusted dylibs only)."""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import sys
from pathlib import Path


def owned(libc: ctypes.CDLL, data: bytes) -> ctypes.c_void_p:
    pointer = libc.malloc(len(data) + 1)
    if not pointer:
        raise MemoryError("malloc failed")
    ctypes.memmove(pointer, data + b"\0", len(data) + 1)
    return pointer


def wire_request(command: dict) -> bytes:
    headers = {"Sender": "Ourin", "Charset": "UTF-8", "ID": command["id"], **command.get("headers", {})}
    headers.update({f"Reference{i}": value for i, value in enumerate(command.get("ref", []))})
    return (
        command.get("method", "GET")
        + " SHIORI/3.0\r\n"
        + "".join(f"{key}: {value}\r\n" for key, value in headers.items())
        + "\r\n"
    ).encode()


def parse_shiori_response(raw: bytes) -> dict:
    text = raw.decode("utf-8", errors="replace")
    status_token = text.split(" ", 2)
    status = int(status_token[1]) if len(status_token) > 1 and status_token[1].isdigit() else 500
    value = ""
    for part in text.split("\r\n"):
        if part.lower().startswith("value:"):
            value = part.split(":", 1)[1].strip()
            break
    return {"ok": 200 <= status < 300, "status": status, "value": value}


def bind_long(module: ctypes.CDLL, libc: ctypes.CDLL) -> tuple:
    module.loadu.argtypes = [ctypes.c_void_p, ctypes.c_long]
    module.loadu.restype = ctypes.c_int
    module.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]
    module.request.restype = ctypes.c_void_p
    module.unload.argtypes = []
    module.unload.restype = ctypes.c_int
    loaded = False

    def do_load(ghost_root: str) -> dict:
        nonlocal loaded
        data = (ghost_root.rstrip("/") + "/").encode()
        loaded = bool(module.loadu(owned(libc, data), len(data)))
        return {"ok": loaded, "status": 200 if loaded else 500, "value": ""}

    def do_request(command: dict) -> dict:
        payload = wire_request(command)
        length = ctypes.c_long(len(payload))
        pointer = module.request(owned(libc, payload), ctypes.byref(length))
        if not pointer:
            return {"ok": False, "status": 500, "value": ""}
        try:
            if not 0 <= length.value <= 64 * 1024 * 1024:
                return {"ok": False, "status": 500, "value": ""}
            raw = ctypes.string_at(pointer, length.value)
        finally:
            libc.free(pointer)
        return parse_shiori_response(raw)

    def do_unload() -> dict:
        nonlocal loaded
        ok = bool(module.unload()) if loaded else True
        loaded = False
        return {"ok": ok, "status": 200 if ok else 500, "value": ""}

    return do_load, do_request, do_unload


def bind_int32(module: ctypes.CDLL, libc: ctypes.CDLL) -> tuple:
    module.loadu.argtypes = [ctypes.c_void_p, ctypes.c_int32]
    module.loadu.restype = ctypes.c_int32
    module.request.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int32)]
    module.request.restype = ctypes.c_void_p
    module.unload.argtypes = []
    module.unload.restype = ctypes.c_int32
    loaded = False

    def do_load(ghost_root: str) -> dict:
        nonlocal loaded
        data = (ghost_root.rstrip("/") + "/").encode()
        count = ctypes.c_int32(len(data))
        loaded = module.loadu(owned(libc, data), count) == 1
        return {"ok": loaded, "status": 200 if loaded else 500, "value": ""}

    def do_request(command: dict) -> dict:
        payload = wire_request(command)
        count = ctypes.c_int32(len(payload))
        pointer = module.request(owned(libc, payload), ctypes.byref(count))
        if not pointer:
            return {"ok": False, "status": 500, "value": ""}
        try:
            if not 0 < count.value <= 64 * 1024 * 1024:
                return {"ok": False, "status": 500, "value": ""}
            raw = ctypes.string_at(pointer, count.value)
        finally:
            libc.free(pointer)
        return parse_shiori_response(raw)

    def do_unload() -> dict:
        nonlocal loaded
        ok = module.unload() == 1 if loaded else True
        loaded = False
        return {"ok": ok, "status": 200 if ok else 500, "value": ""}

    return do_load, do_request, do_unload


def bind_kagari(module: ctypes.CDLL, libc: ctypes.CDLL) -> tuple:
    module.kagari_load.argtypes = [ctypes.c_void_p, ctypes.c_long]
    module.kagari_load.restype = ctypes.c_int
    module.kagari_request.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]
    module.kagari_request.restype = ctypes.c_void_p
    module.kagari_unload.argtypes = [ctypes.c_int]
    module.kagari_unload.restype = ctypes.c_int
    instance = -1

    def do_load(ghost_root: str) -> dict:
        nonlocal instance
        data = (ghost_root.rstrip("/") + "/").encode()
        instance = module.kagari_load(owned(libc, data), ctypes.c_long(len(data)))
        loaded = instance >= 0
        return {"ok": loaded, "status": 200 if loaded else 500, "value": ""}

    def do_request(command: dict) -> dict:
        if instance < 0:
            return {"ok": False, "status": 500, "value": ""}
        payload = wire_request(command)
        length = ctypes.c_long(len(payload))
        pointer = module.kagari_request(instance, owned(libc, payload), ctypes.byref(length))
        if not pointer:
            return {"ok": False, "status": 500, "value": ""}
        try:
            if not 0 <= length.value <= 64 * 1024 * 1024:
                return {"ok": False, "status": 500, "value": ""}
            raw = ctypes.string_at(pointer, length.value)
        finally:
            libc.free(pointer)
        return parse_shiori_response(raw)

    def do_unload() -> dict:
        nonlocal instance
        ok = True
        if instance >= 0:
            # KAGARI returns 1 on success (see engines/kagari/verify_kagari_mosu.py).
            ok = module.kagari_unload(instance) == 1
            instance = -1
        return {"ok": ok, "status": 200 if ok else 500, "value": ""}

    return do_load, do_request, do_unload


def parse_aosora_response(raw: bytes) -> dict:
    # Upstream reports script errors using SHIORI 200 + ErrorLevel. Warnings
    # are not failures; multiple errors use the protocol's SOH separator.
    for line in raw.lower().split(b"\r\n"):
        key, separator, value = line.partition(b":")
        if separator and key == b"errorlevel" and b"error" in [v.strip() for v in value.split(b"\x01")]:
            return {"ok": False, "status": 500, "value": "", "error": "aosora_runtime_error"}
    return parse_shiori_response(raw)


def bind_aosora(module: ctypes.CDLL, libc: ctypes.CDLL) -> tuple:
    module.aosora_load.argtypes = [ctypes.c_void_p, ctypes.c_long]
    module.aosora_load.restype = ctypes.c_long
    module.aosora_request.argtypes = [ctypes.c_long, ctypes.c_void_p, ctypes.POINTER(ctypes.c_long)]
    module.aosora_request.restype = ctypes.c_void_p
    module.aosora_unload.argtypes = [ctypes.c_long]
    module.aosora_unload.restype = ctypes.c_int
    instance = 0

    def do_load(ghost_root: str) -> dict:
        nonlocal instance
        data = (ghost_root.rstrip("/") + "/").encode()
        instance = module.aosora_load(owned(libc, data), ctypes.c_long(len(data)))
        loaded = instance > 0
        return {"ok": loaded, "status": 200 if loaded else 500, "value": ""}

    def do_request(command: dict) -> dict:
        if instance <= 0:
            return {"ok": False, "status": 500, "value": ""}
        payload = wire_request(command)
        length = ctypes.c_long(len(payload))
        pointer = module.aosora_request(instance, owned(libc, payload), ctypes.byref(length))
        if not pointer:
            return {"ok": False, "status": 500, "value": ""}
        try:
            if not 0 <= length.value <= 64 * 1024 * 1024:
                return {"ok": False, "status": 500, "value": ""}
            raw = ctypes.string_at(pointer, length.value)
        finally:
            libc.free(pointer)
        return parse_aosora_response(raw)

    def do_unload() -> dict:
        nonlocal instance
        ok = True
        if instance > 0:
            # Aosora uses positive long IDs; adapter.cpp calls Unload before erase.
            ok = module.aosora_unload(instance) == 1
            instance = 0
        return {"ok": ok, "status": 200 if ok else 500, "value": ""}

    return do_load, do_request, do_unload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--abi", required=True)
    parser.add_argument("--library", required=True, type=Path)
    args = parser.parse_args()
    # Lua print/native printf must never share the JSON transport. Keep a
    # private descriptor before redirecting fd 1, including library init logs.
    protocol = os.fdopen(os.dup(sys.stdout.fileno()), "w", encoding="utf-8")
    os.dup2(sys.stderr.fileno(), sys.stdout.fileno())
    abi = args.abi.lower()
    libc = ctypes.CDLL(None)
    libc.malloc.argtypes = [ctypes.c_size_t]
    libc.malloc.restype = ctypes.c_void_p
    libc.free.argtypes = [ctypes.c_void_p]
    module = ctypes.CDLL(str(args.library))
    if abi == "ukagaka-long":
        do_load, do_request, do_unload = bind_long(module, libc)
    elif abi == "ukagaka-int32":
        do_load, do_request, do_unload = bind_int32(module, libc)
    elif abi == "aosora":
        do_load, do_request, do_unload = bind_aosora(module, libc)
    elif abi == "kagari":
        do_load, do_request, do_unload = bind_kagari(module, libc)
    else:
        print(json.dumps({"ok": False, "error": "unsupported_abi"}), file=protocol, flush=True)
        return 2

    for line in sys.stdin:
        command = json.loads(line)
        if command.get("cmd") == "load":
            response = do_load(command["ghost_root"])
        elif command.get("cmd") == "unload":
            response = do_unload()
        elif command.get("host_op"):
            response = {"host_op": command["host_op"], "ok": False, "error": "harness_unavailable"}
        else:
            response = do_request(command)
        print(json.dumps(response, ensure_ascii=False), file=protocol, flush=True)
    protocol.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
