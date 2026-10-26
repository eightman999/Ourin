import array
import json
import math
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import time
import unittest
import wave

from server import Bridge, Server, parse_speech, render_audio, segments


def tone(path, seconds=1):
    samples = array.array('h', (int(6000 * math.sin(2*math.pi*440*i/48000)) for i in range(int(48000*seconds))))
    with wave.open(str(path), 'wb') as output:
        output.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        output.writeframes(samples.tobytes())


class FakeWorker:
    identity = 'test-worker'
    def __init__(self):
        self.started = threading.Event()
        self.release = threading.Event()
        self.live = True
        self.calls = []
    def alive(self): return self.live
    def cancel(self, identifier): self.release.set()
    def close(self):
        self.live = False
        self.release.set()
    def generate(self, identifier, text, speech, output):
        self.calls.append(text)
        self.started.set()
        self.release.wait(5)
        tone(output, .1)
        return {'ok': True, 'id': identifier}


class ContractTests(unittest.TestCase):
    def test_csv_and_controls(self):
        a = parse_speech('aivoice', 'IrodoriAkari,1,1.2,1,1,150,370,0,0,0,日本語,本文。')
        self.assertEqual(a.text, '日本語,本文。')
        self.assertEqual(segments(a), [('日本語,', 150), ('本文。', 370)])
        c = parse_speech('cevio', 'IrodoriAoi,50,50,50,50,50,喜びMySep25,,悲しみMySep50,本文,末尾')
        self.assertEqual((c.speed, c.pitch, c.volume), (1, 1, 1))
        self.assertIn('喜びの感情を0.25', c.instructions)
        self.assertEqual(c.text, '本文,末尾')

    def test_prosody_parameters_and_question_marks_survive(self):
        a = parse_speech('aivoice', 'IrodoriAkari,1,1,1,0.8,150,370,0,0,0,本当？')
        b = parse_speech('aivoice', 'IrodoriAkari,1,1,1,1.2,150,370,0,0,0,本当？')
        self.assertNotEqual(a.instructions, b.instructions)
        self.assertEqual(segments(a), [('本当？', 370)])
        a = parse_speech('cevio', 'IrodoriAkari,50,50,50,41,50,,,,本当？')
        b = parse_speech('cevio', 'IrodoriAkari,50,50,50,59,50,,,,本当？')
        self.assertNotEqual(a.instructions, b.instructions)

    def test_refuse_bad_parameters(self):
        good = 'IrodoriAkari,1,1.2,1,1,150,370,0,0,0,本文'
        for value in [good.replace(',1,1.2', ',nan,1.2'), good.replace(',1.2,', ',4.1,'),
                      good.replace('IrodoriAkari', 'unknown'), good + '\x00', good.rsplit(',', 1)[0]]:
            with self.assertRaises(ValueError): parse_speech('aivoice', value)
        with self.assertRaises(ValueError):
            parse_speech('cevio', 'IrodoriAoi,50,50,50,50,50,喜びMySep25,喜びMySep10,,本文')

    @unittest.skipUnless(shutil.which('ffmpeg'), 'ffmpeg required')
    def test_independent_speed_pitch_gain(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tone(root/'raw.wav')
            speech = parse_speech('aivoice', 'IrodoriAkari,0.5,2,1.5,1,150,370,0,0,0,本文')
            render_audio(root/'raw.wav', root/'out.wav', speech, shutil.which('ffmpeg'))
            with wave.open(str(root/'out.wav')) as wav:
                self.assertAlmostEqual(wav.getnframes()/wav.getframerate(), .5, delta=.04)
                samples = array.array('h', wav.readframes(wav.getnframes()))
            self.assertLess(max(samples), 3600)
            crossings = sum(a <= 0 < b for a, b in zip(samples, samples[1:]))
            self.assertAlmostEqual(crossings/(len(samples)/48000), 660, delta=30)

    @unittest.skipUnless(shutil.which('ffmpeg'), 'ffmpeg required')
    def test_replace_and_unload_discard_pending_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            worker = FakeWorker()
            bridge = Bridge(worker, Path(directory), shutil.which('ffmpeg'), False)
            def call(action, argument=''):
                return bridge.handle(dict(product='aivoice', session='test', action=action, argument=argument))
            try:
                call('start')
                prefix = 'IrodoriAkari,1,1,1,1,150,370,0,0,0,'
                call('client', prefix+'古い発話')
                self.assertTrue(worker.started.wait(2))
                call('client', prefix+'新しい発話')
                call('client', 'end')
                worker.release.set()
                deadline = time.monotonic()+4
                while bridge.active and time.monotonic()<deadline: time.sleep(.02)
                self.assertEqual(worker.calls, ['古い発話'])
                states = [entry['state'] for entry in bridge.history]
                self.assertIn('cancelled', states)
                self.assertIn('cancelled-before-generation', states)
                self.assertNotIn('audio-ready', states)
                self.assertEqual(call('check')['result'], 'False')
            finally: bridge.close()

    def test_wire_errors_and_voice_list(self):
        with tempfile.TemporaryDirectory() as directory:
            bridge = Bridge(FakeWorker(), Path(directory), 'unused', False)
            server = Server(('127.0.0.1', 0), bridge)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            def call(message):
                with socket.create_connection(server.server_address) as sock:
                    sock.sendall((json.dumps(message)+'\n').encode())
                    return json.loads(sock.makefile('rb').readline())
            base = dict(product='cevio', session='test')
            try:
                self.assertFalse(call([])['ok'])
                self.assertTrue(call(dict(base, action='start'))['ok'])
                self.assertEqual(call(dict(base, action='client', argument='GetCharOptions_IrodoriAkari'))['result'], ',喜び,怒り,悲しみ')
                self.assertFalse(call(dict(base, action='execute', argument='/bin/sh'))['ok'])
                bridge.worker.live = False
                self.assertEqual(call(dict(base, action='check'))['result'], 'False')
                self.assertFalse(call(dict(base, action='client', argument='GetCharList'))['ok'])
            finally:
                server.shutdown()
                server.server_close()
                bridge.close()


if __name__ == '__main__': unittest.main()
