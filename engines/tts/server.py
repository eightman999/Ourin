#!/usr/bin/env python3
"""Opt-in loopback bridge for the original CeVIO/AIVOICE plugin protocols.

Uses Irodori voices, not the commercial engines or their voice identities.
No shell, remote endpoint, or user-selected executable is exposed over the socket.
"""
from __future__ import annotations

import argparse
from collections import OrderedDict, deque
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socketserver
import subprocess
import sys
import threading
import time
import wave

VOICES = {
    'IrodoriAkari': '明るく親しみやすい成人女性の声。自然な日本語で話す。',
    'IrodoriAoi': '落ち着いた成人男性の声。自然な日本語で穏やかに話す。',
    'IrodoriNagi': '柔らかく中性的な成人の声。自然な日本語ではっきり話す。',
}
EMOTIONS = ('喜び', '怒り', '悲しみ')
LIMIT = 65536


def number(raw, low, high):
    value = float(raw)
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError('voice parameter out of range')
    return value


@dataclass(frozen=True)
class Speech:
    voice: str
    text: str
    volume: float
    speed: float
    pitch: float
    middle_ms: float
    long_ms: float
    instructions: str


def parse_speech(product, argument):
    if product not in ('cevio', 'aivoice') or not isinstance(argument, str):
        raise ValueError('invalid product or argument')
    fields = argument.split(',', 9 if product == 'cevio' else 10)
    if len(fields) != (10 if product == 'cevio' else 11):
        raise ValueError('invalid speech field count')
    voice = fields[0]
    if voice not in VOICES:
        raise ValueError('unknown Irodori voice; select a voice in the original plugin menu')
    if product == 'cevio':
        volume, speed, tone, alpha, tone_scale = [number(x, 0, 100) for x in fields[1:6]]
        emotions = dict.fromkeys(EMOTIONS, 0.0)
        seen = set()
        for field in fields[6:9]:
            if not field:
                continue
            name, separator, raw = field.partition('MySep')
            if not separator or name not in emotions or name in seen:
                raise ValueError('invalid CeVIO emotion component')
            seen.add(name)
            emotions[name] = number(raw, 0, 100) / 100
        # Explicit approximation: the proprietary engines' transfer curves are
        # unavailable. Midpoint is neutral; DSP applies actual speed/pitch/gain.
        volume /= 50
        speed = 2 ** ((speed - 50) / 50)
        pitch = 2 ** ((tone - 50) / 50)
        expressiveness = tone_scale / 50
        timbre = f'声の明るさは0から100の尺度で{alpha:g}。50が自然な声質。'
        middle, long = 150, 370
    else:
        volume = number(fields[1], 0, 5)
        speed = number(fields[2], .5, 4)
        pitch = number(fields[3], .5, 2)
        expressiveness = number(fields[4], 0, 2)
        middle = number(fields[5], 80, 500)
        long = number(fields[6], 80, 2000)
        emotions = {name: number(raw, 0, 1) for name, raw in zip(EMOTIONS, fields[7:10])}
        timbre = ''
    text = fields[-1]
    if len(text) > 4000 or any(ord(c) < 32 and c not in '\n\t' for c in text):
        raise ValueError('invalid or oversized speech text')
    # The original YAYA dictionary supplies plain text. Do not interpret it as
    # commands, paths or interpolation syntax in this service.
    style = f'抑揚の強さは0から2の尺度で{expressiveness:g}。1が自然な抑揚。'
    style += ''.join(f'{name}の感情を{value:.2f}の強さで表現する。' for name, value in emotions.items() if value)
    return Speech(voice, text, volume, speed, pitch, middle, long, VOICES[voice] + timbre + style)


def segments(speech):
    """Preserve text/comma boundaries and insert requested punctuation pauses."""
    parts = []
    for match in re.finditer(r'([^、,。！？!?\n]+)([、,。！？!?\n]*)', speech.text):
        text, punctuation = match.groups()
        text = text.strip()
        if not text:
            continue
        pause = speech.long_ms if re.search(r'[。！？!?\n]', punctuation) else speech.middle_ms if punctuation else 0
        # Bounded short generation units keep cancellation useful for long talks.
        for start in range(0, len(text), 120):
            final = start + 120 >= len(text)
            parts.append((text[start:start+120] + (punctuation if final else ''), pause if final else 0))
    if len(parts) > 64:
        raise ValueError('too many speech segments')
    return parts


def tempo_filters(ratio):
    filters = []
    while ratio < .5:
        filters.append('atempo=0.5')
        ratio /= .5
    while ratio > 2:
        filters.append('atempo=2')
        ratio /= 2
    filters.append(f'atempo={ratio:.8f}')
    return filters


def render_audio(raw, target, speech, ffmpeg):
    with wave.open(str(raw)) as source:
        rate = source.getframerate()
    filters = [f'asetrate={rate * speech.pitch:.8f}', f'aresample={rate}']
    filters += tempo_filters(speech.speed / speech.pitch)
    filters += [f'volume={speech.volume:.8f}', 'alimiter=limit=0.98:level=false']
    subprocess.run([ffmpeg, '-nostdin', '-v', 'error', '-y', '-i', str(raw),
                    '-af', ','.join(filters), '-ac', '1', '-c:a', 'pcm_s16le', str(target)],
                   check=True, timeout=60, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)


class Worker:
    def __init__(self, python, model, root):
        self.root = root
        weights = Path(model) / 'model.safetensors'
        self.identity = str(Path(model).resolve()) + str(weights.stat().st_mtime_ns) + str(weights.stat().st_size)
        self.process = subprocess.Popen([python, str(Path(__file__).with_name('irodori_worker.py')),
                                         '--model', str(model), '--output-dir', str(root)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        self.ready = self.read(300)
        if not self.ready.get('ready'):
            self.close()
            raise RuntimeError('Irodori model did not become ready')

    def read(self, timeout):
        if not select.select([self.process.stdout], [], [], timeout)[0]:
            self.close()
            raise TimeoutError('Irodori worker deadline exceeded')
        line = self.process.stdout.readline(LIMIT + 1)
        if not line or len(line) > LIMIT or not line.endswith('\n'):
            raise RuntimeError('Irodori worker exited or invalid reply')
        return json.loads(line)

    def alive(self):
        return self.process.poll() is None

    def generate(self, identifier, text, speech, output):
        request = dict(id=identifier, text=text, voice=speech.voice, instructions=speech.instructions,
                       speed=1.0, output=str(output))
        self.process.stdin.write(json.dumps(request, ensure_ascii=False) + '\n')
        self.process.stdin.flush()
        result = self.read(180)
        if result.get('cancelled') and result.get('id') == identifier:
            return result
        if result.get('duration_limited'):
            raise RuntimeError('Irodori hit duration limit; speech may be truncated')
        if not result.get('ok') or result.get('id') != identifier:
            raise RuntimeError(result.get('error', 'invalid worker generation response'))
        if not output.is_file():
            raise RuntimeError('worker produced no audio')
        return result

    def cancel(self, identifier):
        marker = self.root / ('.cancel-' + hashlib.sha256(str(identifier).encode()).hexdigest())
        marker.touch(exist_ok=True)
        if self.alive():
            os.kill(self.process.pid, signal.SIGUSR1)

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()


class Bridge:
    def __init__(self, worker, root, ffmpeg, play=True):
        self.worker, self.root, self.ffmpeg, self.play = worker, root, ffmpeg, play
        self.lock = threading.Condition(threading.RLock())
        self.sessions = {}
        self.pending = OrderedDict()
        self.epochs = {}
        self.history = deque(maxlen=32)
        self.active = None
        self.generating = None
        self.player = None
        self.closed = False
        self.sequence = 0
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def cancel(self, session):
        self.epochs[session] = self.epochs.get(session, 0) + 1
        old = self.pending.pop(session, None)
        if old:
            self.record(old[0], session, 'cancelled-before-generation')
        if self.active and self.active[1] == session and self.generating:
            self.worker.cancel(self.generating)
        if self.active and self.active[1] == session and self.player:
            self.player.terminate()
            try:
                self.player.wait(1)
            except subprocess.TimeoutExpired:
                self.player.kill()
                self.player.wait()
            self.player = None

    def record(self, identifier, session, state, **details):
        with self.lock:
            self.history.append(dict(id=identifier, session=session, state=state, **details))

    def handle(self, request):
        if not isinstance(request, dict):
            raise ValueError('object required')
        product, session, action = (request.get(k) for k in ('product', 'session', 'action'))
        if product not in ('cevio', 'aivoice') or not isinstance(session, str) or not re.fullmatch(r'[A-Za-z0-9_.:-]{1,160}', session):
            raise ValueError('invalid product/session')
        argument = request.get('argument', '')
        if not isinstance(argument, str) or len(argument.encode('utf-8')) > 32000:
            raise ValueError('invalid argument')
        with self.lock:
            if action == 'status':
                return dict(ok=True, result='', ready=self.worker.alive(), playing=bool(self.player),
                            active=self.active, pending=len(self.pending), history=list(self.history))
            if action == 'start':
                if not self.worker.alive():
                    raise RuntimeError('Irodori worker unavailable')
                if len(self.sessions) >= 64 and session not in self.sessions:
                    raise ValueError('too many sessions')
                if session in self.sessions and self.sessions[session] != product:
                    raise ValueError('session product mismatch')
                self.sessions[session] = product
                return dict(ok=True, result='True')
            if action == 'check':
                return dict(ok=True, result='True' if self.worker.alive() and self.sessions.get(session) == product else 'False')
            if self.sessions.get(session) != product:
                raise ValueError('session not started')
            if action == 'stop' or (action == 'client' and argument == 'end'):
                self.cancel(session)
                self.sessions.pop(session, None)
                self.lock.notify_all()
                return dict(ok=True, result='endClient')
            if action != 'client':
                raise ValueError('unknown action')
            if not self.worker.alive():
                raise RuntimeError('Irodori worker unavailable')
            if argument == 'GetCharList':
                return dict(ok=True, result=(',' if product == 'cevio' else '') + ','.join(VOICES))
            if product == 'cevio' and argument.startswith('GetCharOptions_'):
                if argument.removeprefix('GetCharOptions_') not in VOICES:
                    raise ValueError('unknown voice')
                return dict(ok=True, result=',' + ','.join(EMOTIONS))
            speech = parse_speech(product, argument)
            chunks = segments(speech)
            self.cancel(session)
            self.sequence += 1
            identifier = str(self.sequence)
            self.pending[session] = (identifier, self.epochs[session], speech, chunks)
            self.record(identifier, session, 'accepted', text_sha256=hashlib.sha256(speech.text.encode()).hexdigest(),
                        voice=speech.voice, segments=len(chunks))
            self.lock.notify_all()
            return dict(ok=True, result='Server read OK.', id=identifier)

    def valid(self, session, epoch):
        return not self.closed and self.epochs.get(session) == epoch and session in self.sessions

    def run(self):
        while True:
            with self.lock:
                self.lock.wait_for(lambda: self.pending or self.closed)
                if self.closed:
                    return
                session, (identifier, epoch, speech, chunks) = self.pending.popitem(last=False)
                self.active = (identifier, session)
            started = time.monotonic()
            files = []
            try:
                for index, (text, pause) in enumerate(chunks):
                    with self.lock:
                        if not self.valid(session, epoch):
                            break
                    key = hashlib.sha256(json.dumps([self.worker.identity, text, speech.__dict__], ensure_ascii=False, sort_keys=True).encode()).hexdigest()
                    audio = self.root / f'{key}.wav'
                    if audio.is_symlink():
                        raise ValueError('audio cache must not be a symlink')
                    if not audio.exists():
                        raw = self.root / f'{key}.raw.wav'
                        try:
                            job_id = f'{identifier}-{index}'
                            with self.lock:
                                if not self.valid(session, epoch):
                                    break
                                self.generating = job_id
                            result = self.worker.generate(job_id, text, speech, raw)
                            with self.lock:
                                self.generating = None
                                if not self.valid(session, epoch) or result.get('cancelled'):
                                    break
                            render_audio(raw, audio, speech, self.ffmpeg)
                        finally:
                            with self.lock:
                                self.generating = None
                            (self.root / ('.cancel-' + hashlib.sha256(f'{identifier}-{index}'.encode()).hexdigest())).unlink(missing_ok=True)
                            raw.unlink(missing_ok=True)
                    with wave.open(str(audio)) as wav:
                        duration = wav.getnframes() / wav.getframerate()
                    with self.lock:
                        if not self.valid(session, epoch):
                            break
                        files.append(dict(path=str(audio), duration=duration, pause_ms=pause))
                        self.record(identifier, session, 'audio-ready', file=str(audio), duration=duration,
                                    first_audio_seconds=time.monotonic()-started, index=index)
                        if self.play and speech.volume > 0:
                            self.player = subprocess.Popen(['/usr/bin/afplay', str(audio)], stdin=subprocess.DEVNULL,
                                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            player = self.player
                        else:
                            player = None
                    if player:
                        code = player.wait()
                        with self.lock:
                            if self.valid(session, epoch) and code:
                                raise RuntimeError('audio playback failed')
                            if self.player is player:
                                self.player = None
                    if pause and self.play:
                        with self.lock:
                            self.lock.wait_for(lambda: not self.valid(session, epoch), timeout=pause/1000)
                with self.lock:
                    state = 'completed' if self.valid(session, epoch) else 'cancelled'
                    self.record(identifier, session, state, elapsed_seconds=time.monotonic()-started,
                                files=files, playback_enabled=self.play)
            except Exception as error:
                with self.lock:
                    self.record(identifier, session, 'failed' if self.valid(session, epoch) else 'cancelled', error=str(error))
            finally:
                with self.lock:
                    self.active = None
                # Only service-owned hashed WAVs, never references or user assets.
                cached = sorted(self.root.glob('[0-9a-f]' * 64 + '.wav'), key=lambda p: p.stat().st_mtime, reverse=True)
                size = 0
                for index, path in enumerate(cached):
                    size += path.stat().st_size
                    if index >= 128 or size > 256 * 1024 * 1024:
                        path.unlink(missing_ok=True)

    def close(self):
        with self.lock:
            self.closed = True
            for session in list(self.sessions):
                self.cancel(session)
            self.lock.notify_all()
        self.worker.close()
        self.thread.join(10)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
    def __init__(self, address, bridge):
        self.bridge = bridge
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(address, Handler)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        super().process_request(request, address)

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(2)
        try:
            line = self.rfile.readline(LIMIT + 1)
            if len(line) > LIMIT or not line.endswith(b'\n'):
                raise ValueError('invalid request framing')
            result = self.server.bridge.handle(json.loads(line))
        except Exception as error:
            result = dict(ok=False, result='', error=str(error))
        try:
            self.wfile.write((json.dumps(result, ensure_ascii=False) + '\n').encode())
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python', default=sys.executable)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--port', type=int, default=50731)
    parser.add_argument('--no-play', action='store_true', help='Generate WAVs only; does not verify audible playback')
    args = parser.parse_args()
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        parser.error('ffmpeg is required for independent pitch/speed/volume control')
    root = args.work_dir.resolve()
    root.mkdir(parents=True, exist_ok=True)
    worker = Worker(args.python, args.model.resolve(), root)
    bridge = Bridge(worker, root, ffmpeg, not args.no_play)
    try:
        with Server(('127.0.0.1', args.port), bridge) as server:
            def stop(*_):
                threading.Thread(target=server.shutdown, daemon=True).start()
            signal.signal(signal.SIGTERM, stop)
            signal.signal(signal.SIGINT, stop)
            print(json.dumps(dict(ready=True, port=server.server_address[1], backend='irodori-mlx',
                                  model=str(args.model), playback=not args.no_play)), flush=True)
            server.serve_forever(poll_interval=.1)
    finally:
        bridge.close()


if __name__ == '__main__':
    main()
