#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Independent, read-only DDE client. Windows + TMIDI Player required.

Only loopback is exposed. Use an explicitly configured SSH local forward to
reach this listener from a Mac; do not bind it to a network interface.
Windows execution has not been verified by the macOS regression suite.
"""
import argparse
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import socket
import time
import uuid

PROTOCOL = "ourin-tmidi-dde/1"


class DDEClient:
    def __init__(self):
        if os.name != "nt":
            raise RuntimeError("Windows DDEML and TMIDI Player are required")
        self.api = ctypes.WinDLL("user32", use_last_error=True)
        handle, uint, dword = ctypes.c_void_p, wintypes.UINT, wintypes.DWORD
        callback_type = ctypes.WINFUNCTYPE(handle, uint, uint, handle, handle,
                                         handle, handle, ctypes.c_size_t, ctypes.c_size_t)
        self.callback = callback_type(lambda *args: None)
        signatures = {
            "DdeInitializeW": ([ctypes.POINTER(dword), callback_type, dword, dword], uint),
            "DdeCreateStringHandleW": ([dword, wintypes.LPCWSTR, ctypes.c_int], handle),
            "DdeFreeStringHandle": ([dword, handle], wintypes.BOOL),
            "DdeConnectList": ([dword, handle, handle, handle, handle], handle),
            "DdeQueryNextServer": ([handle, handle], handle),
            "DdeDisconnectList": ([handle], wintypes.BOOL),
            "DdeClientTransaction": ([handle, dword, handle, handle, uint, uint, dword, ctypes.POINTER(dword)], handle),
            "DdeGetData": ([handle, handle, dword, dword], dword),
            "DdeFreeDataHandle": ([handle], wintypes.BOOL),
            "DdeGetLastError": ([dword], uint),
            "DdeUninitialize": ([dword], wintypes.BOOL),
            "PeekMessageW": ([ctypes.POINTER(wintypes.MSG), handle, uint, uint, uint], wintypes.BOOL),
            "TranslateMessage": ([ctypes.POINTER(wintypes.MSG)], wintypes.BOOL),
            "DispatchMessageW": ([ctypes.POINTER(wintypes.MSG)], ctypes.c_ssize_t),
        }
        for name, (args, result) in signatures.items():
            function = getattr(self.api, name)
            function.argtypes, function.restype = args, result
        self.instance = dword(0)
        self.conversations = None
        code = self.api.DdeInitializeW(ctypes.byref(self.instance), self.callback, 0x10, 0)
        if code:
            raise RuntimeError(f"DdeInitializeW failed: {code}")
        self.service = self.api.DdeCreateStringHandleW(self.instance, "TMIDI", 1200)
        self.topic = self.api.DdeCreateStringHandleW(self.instance, "TMIDI", 1200)
        if not self.service or not self.topic:
            self.close()
            raise RuntimeError("DDE string handle creation failed")

    def pump(self):
        message = wintypes.MSG()
        while self.api.PeekMessageW(ctypes.byref(message), None, 0, 0, 1):
            self.api.TranslateMessage(ctypes.byref(message))
            self.api.DispatchMessageW(ctypes.byref(message))

    def query(self, conversation, item, deadline):
        remaining = int((deadline - time.monotonic()) * 1000)
        if remaining <= 0:
            raise TimeoutError("DDE snapshot deadline exceeded")
        name = self.api.DdeCreateStringHandleW(self.instance, item, 1200)
        if not name:
            raise RuntimeError("DDE item handle unavailable")
        data = None
        try:
            # CF_TEXT=1; XTYP_REQUEST=0x20B0. Never XTYP_EXECUTE/POKE.
            data = self.api.DdeClientTransaction(None, 0, conversation, name,
                                                 1, 0x20B0, min(250, remaining), None)
            if not data:
                code = self.api.DdeGetLastError(self.instance)
                raise RuntimeError(f"DDE request failed: {code}")
            size = self.api.DdeGetData(data, None, 0, 0)
            if size > 32768:
                raise ValueError("DDE value too large")
            if not size:
                return ""
            buffer = ctypes.create_string_buffer(size)
            copied = self.api.DdeGetData(data, buffer, size, 0)
            return bytes(buffer.raw[:copied]).rstrip(b"\0").decode("mbcs", errors="strict")
        finally:
            if data:
                self.api.DdeFreeDataHandle(data)
            self.api.DdeFreeStringHandle(self.instance, name)

    def snapshot(self):
        self.pump()
        # DdeConnectList updates the existing list and removes dead conversations.
        self.conversations = self.api.DdeConnectList(self.instance, self.service, self.topic,
                                                      self.conversations, None)
        if not self.conversations:
            code = self.api.DdeGetLastError(self.instance)
            raise RuntimeError(f"TMIDI DDE service unavailable: {code}")
        deadline = time.monotonic() + 1.2
        instances = []
        previous = None
        while True:
            conversation = self.api.DdeQueryNextServer(self.conversations, previous)
            if not conversation:
                break
            if len(instances) >= 32:
                raise ValueError("Too many TMIDI instances")
            previous = conversation
            status = self.query(conversation, "getstatus", deadline)
            track, filename, title = "", "", ""
            if status == "play":
                track = self.query(conversation, "getplayfile", deadline) or "0"
                if len(track) > 64 or any(c not in "0123456789" for c in track):
                    raise ValueError("Invalid TMIDI track index")
                filename = self.query(conversation, "getfilename " + track, deadline)
                title = self.query(conversation, "gettitle " + track, deadline)
            instances.append({"id": format(conversation, "x"), "getstatus": status,
                              "getplayfile": track, "getfilename": filename,
                              "gettitle": title, "wrd": wrd_type(filename)})
        return instances

    def close(self):
        if self.conversations:
            self.api.DdeDisconnectList(self.conversations)
            self.conversations = None
        for name in ("service", "topic"):
            value = getattr(self, name, None)
            if value:
                self.api.DdeFreeStringHandle(self.instance, value)
                setattr(self, name, None)
        self.api.DdeUninitialize(self.instance)


def wrd_type(filename):
    path = Path(filename)
    if path.suffix.lower() == ".neo":
        return "NeoWRD"
    if path.suffix and path.with_suffix(".sry").is_file():
        return "SherryWRD"
    if path.suffix and any(path.with_suffix(s).is_file() for s in (".wrd", ".dv")):
        return "MIMPIWRD"
    return "NoWRD"


def answer(request, client, session):
    expected = {"protocol": PROTOCOL, "service": "TMIDI", "topic": "TMIDI", "query": "snapshot"}
    if request != expected:
        return {"protocol": PROTOCOL, "session": session, "error": "unsupported_query"}
    try:
        return {"protocol": PROTOCOL, "session": session, "instances": client.snapshot()}
    except (OSError, RuntimeError, ValueError) as error:
        # Operational failure cannot look like an empty successful snapshot.
        return {"protocol": PROTOCOL, "session": session, "error": type(error).__name__}


def serve(client, port):
    session = str(uuid.uuid4())
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", port))
        listener.listen(4)
        listener.settimeout(0.1)
        print(f"TMIDI DDE bridge listening on 127.0.0.1:{port}; read-only queries")
        while True:
            client.pump()
            try:
                connection, _ = listener.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(1)
                try:
                    request = bytearray()
                    while b"\n" not in request and len(request) <= 4096:
                        chunk = connection.recv(512)
                        if not chunk:
                            break
                        request.extend(chunk)
                    if len(request) > 4096 or not request.endswith(b"\n"):
                        continue
                    result = answer(json.loads(request), client, session)
                    payload = json.dumps(result, ensure_ascii=False).encode("utf-8") + b"\n"
                    if len(payload) <= 1024 * 1024:
                        connection.sendall(payload)
                except (OSError, ValueError):
                    continue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=50002)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be 1..65535")
    if os.name != "nt":
        parser.error("Windows is required; no DDE fallback is simulated")
    client = DDEClient()
    try:
        serve(client, args.port)
    except KeyboardInterrupt:
        pass
    finally:
        client.close()


if __name__ == "__main__":
    main()
