#!/usr/bin/env python3
"""Protocol/path regression tests; no model download or MLX import required."""
import importlib.util
import hashlib
import json
import os
import signal
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('irodori_worker', Path(__file__).with_name('irodori_worker.py'))
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.addCleanup(self.temporary.cleanup)

    def parse(self, **changes):
        request = {'id': 'one', 'text': 'こんにちは。', 'voice': 'IrodoriAkari', 'output': 'one.wav'}
        request.update(changes)
        return worker.parse_request(json.dumps(request), self.root)

    def test_valid_request_and_default_output(self):
        self.assertEqual(self.parse()[-1], self.root / 'one.wav')
        self.assertEqual(self.parse(output=None)[-1].parent, self.root)

    def test_no_output_escape(self):
        for path in ('../escape.wav', '/tmp/escape.wav', 'one.txt'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.parse(output=path)

    def test_no_symlink_escape(self):
        (self.root / 'outside').symlink_to('/tmp', target_is_directory=True)
        with self.assertRaises(ValueError):
            self.parse(output='outside/escape.wav')

    def test_preserves_existing_output_and_reference_cache(self):
        (self.root / 'one.wav').write_bytes(b'original')
        (self.root / 'references').mkdir()
        for name in ('one.wav', 'references/voice.wav'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.parse(output=name)
        self.assertEqual((self.root / 'one.wav').read_bytes(), b'original')

    def test_rejects_empty_long_and_control_text(self):
        for text in (' ', 'あ' * 241, 'abc\x00def', 123):
            with self.subTest(text=repr(text)[:40]), self.assertRaises(ValueError):
                self.parse(text=text)

    def test_unknown_voice_is_not_silently_substituted(self):
        with self.assertRaises(ValueError):
            self.parse(voice='CeVIO')

    def test_rate_must_be_applied_by_host(self):
        for speed in (True, 0, 1.2, float('nan'), float('inf'), '1'):
            with self.subTest(speed=speed), self.assertRaises(ValueError):
                self.parse(speed=speed)
        self.assertEqual(self.parse(speed=1.0)[0], 'one')

    def test_id_and_instructions_are_bounded(self):
        for changes in ({'id': True}, {'id': 'a' * 101}, {'instructions': 'a' * 1001}, {'instructions': []}):
            with self.subTest(changes=str(changes)[:40]), self.assertRaises(ValueError):
                self.parse(**changes)

    def test_atomic_output_does_not_overwrite(self):
        class FakeSoundFile:
            @staticmethod
            def write(path, audio, rate, subtype):
                Path(path).write_bytes(b'new')
        instance = worker.Worker.__new__(worker.Worker)
        instance.sf = FakeSoundFile
        target = self.root / 'one.wav'
        instance.write_audio(target, None, 48000)
        self.assertEqual(target.read_bytes(), b'new')
        target.write_bytes(b'original')
        with self.assertRaises(FileExistsError):
            instance.write_audio(target, None, 48000)
        self.assertEqual(target.read_bytes(), b'original')
        self.assertEqual(list(self.root.glob('.irodori-*')), [])


class CancellationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.addCleanup(self.temporary.cleanup)
        self.cancellation = worker.Cancellation(self.root)

    def marker(self, identifier):
        return self.root / ('.cancel-' + hashlib.sha256(str(identifier).encode()).hexdigest())

    def test_idle_signal_does_not_cancel_next_request(self):
        self.cancellation.check()
        self.cancellation.begin('next')
        self.cancellation.check()
        self.cancellation.finish()

    def test_cancel_before_request_dispatch(self):
        self.marker('early').touch()
        self.cancellation.check()  # signal came before stdin was consumed
        with self.assertRaises(worker.Cancelled):
            self.cancellation.begin('early')
        self.cancellation.finish()
        self.assertFalse(self.marker('early').exists())

    def test_cancel_during_wav_commit_leaves_complete_file_and_no_temp(self):
        cancellation = self.cancellation
        marker = self.marker('writing')
        class FakeSoundFile:
            @staticmethod
            def write(path, audio, rate, subtype):
                marker.touch()
                os.kill(os.getpid(), signal.SIGUSR1)
                Path(path).write_bytes(b'complete-wave')
        instance = worker.Worker.__new__(worker.Worker)
        instance.sf = FakeSoundFile
        previous = signal.signal(signal.SIGUSR1, cancellation.check)
        try:
            cancellation.begin('writing')
            with self.assertRaises(worker.Cancelled):
                instance.write_audio(self.root / 'complete.wav', None, 48000)
        finally:
            signal.signal(signal.SIGUSR1, previous)
            cancellation.finish()
        self.assertEqual((self.root / 'complete.wav').read_bytes(), b'complete-wave')
        self.assertFalse(marker.exists())
        self.assertEqual(list(self.root.glob('.irodori-*')), [])

    def test_active_cancel_disarms_before_cleanup_and_next_request_runs(self):
        self.cancellation.begin('active')
        self.marker('other').touch()
        self.cancellation.check()  # wrong request marker cannot stop this request
        self.marker('active').touch()
        with self.assertRaises(worker.Cancelled):
            self.cancellation.check()
        self.cancellation.check()  # repeated signals must not interrupt finally
        self.cancellation.finish()
        self.assertFalse(self.marker('active').exists())
        self.assertTrue(self.marker('other').exists())
        self.cancellation.begin('next')
        self.cancellation.check()
        self.cancellation.finish()


if __name__ == '__main__':
    unittest.main()
