import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import json
import sys
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('voice', ROOT / 'modules/desktop/_voice_dictation.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


class Dictation(unittest.TestCase):
    def setUp(self):
        voice.STOP.clear()

    def exercise(self, mode, transcript='Olá mundo', rewrite='Resposta revisada', failure=None, clipboard='Mensagem copiada'):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            def run(args, **kwargs):
                calls.append((args, kwargs))
                return clipboard if args[0] == 'wl-paste' else ''
            def capture(path):
                calls.append((['capture', str(path)], {}))
                path.write_bytes(b'private audio')
            with patch.object(voice, 'run', run), patch.object(voice, 'capture', capture), patch.object(voice, 'transcribe', side_effect=RuntimeError('transcription failed') if failure else None, return_value=transcript), patch.object(voice, 'rewrite', return_value=rewrite) as transform:
                try:
                    voice.dictate(mode, pathlib.Path(directory))
                except (RuntimeError, voice.Cancelled):
                    pass
            self.assertFalse(pathlib.Path(directory, 'capture.wav').exists())
            return calls, transform

    def test_plain_copies_transcript_without_reading_clipboard_or_llm(self):
        calls, transform = self.exercise('plain')
        copied = [kw['input'] for a, kw in calls if 'wl-copy' in a]
        self.assertEqual(copied, ['Olá mundo'])
        self.assertFalse(any(a[0] == 'wl-paste' for a, _ in calls))
        transform.assert_not_called()

    def test_context_snapshot_precedes_capture_and_is_bound_to_rewrite(self):
        calls, transform = self.exercise('context')
        read = next(i for i, (a, _) in enumerate(calls) if a[0] == 'wl-paste')
        start = next(i for i, (a, _) in enumerate(calls) if a[0] == 'capture')
        self.assertLess(read, start)
        transform.assert_called_once_with('Olá mundo', 'Mensagem copiada')
        self.assertEqual([kw['input'] for a, kw in calls if 'wl-copy' in a], ['Resposta revisada'])

    def test_no_speech_does_not_replace_clipboard(self):
        calls, _ = self.exercise('plain', transcript='  ')
        self.assertFalse(any('wl-copy' in a for a, _ in calls))

    def test_transcription_failure_does_not_replace_clipboard(self):
        calls, _ = self.exercise('plain', failure=True)
        self.assertFalse(any('wl-copy' in a for a, _ in calls))

    def test_empty_rewrite_does_not_replace_clipboard(self):
        calls, _ = self.exercise('context', rewrite='')
        self.assertFalse(any('wl-copy' in a for a, _ in calls))



    def test_oversize_context_does_not_open_microphone(self):
        calls, transform = self.exercise('context', clipboard='x' * 12001)
        self.assertFalse(any(a[0] == 'capture' for a, _ in calls))
        transform.assert_not_called()

    def test_cancellation_before_commit_does_not_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(voice, 'capture', side_effect=voice.Cancelled), patch.object(voice, 'run') as run:
                with self.assertRaises(voice.Cancelled):
                    voice.dictate('plain', pathlib.Path(directory))
            self.assertFalse(any('wl-copy' in call.args[0] for call in run.call_args_list))

    def test_local_fallback_uses_loopback_json_and_requires_complete_result(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            'done': True, 'done_reason': 'stop', 'message': {'content': 'Texto final'}
        }).encode()
        opener = MagicMock()
        opener.open.return_value = response
        with patch.object(voice.urllib.request, 'build_opener', return_value=opener):
            self.assertEqual(voice.rewrite('ditado', 'copiado'), 'Texto final')
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, 'http://127.0.0.1:11435/api/chat')
        body = json.loads(request.data)
        self.assertFalse(body['stream'])
        self.assertEqual(json.loads(body['messages'][1]['content']),
                         {'dictation': 'ditado', 'copied_context': 'copiado'})
        response.__enter__.return_value.read.return_value = b'{"done":false,"message":{"content":"partial"}}'
        with patch.object(voice.urllib.request, 'build_opener', return_value=opener):
            with self.assertRaises(RuntimeError):
                voice.rewrite('ditado', 'copiado')

    def test_length_limited_rewrite_is_rejected(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"done":true,"done_reason":"length","message":{"content":"partial"}}'
        opener = MagicMock()
        opener.open.return_value = response
        with patch.object(voice.urllib.request, 'build_opener', return_value=opener):
            with self.assertRaises(RuntimeError):
                voice.rewrite('dictation', 'context')

    def test_cancellation_during_rewrite_does_not_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(voice, 'run', return_value='context') as run, patch.object(voice, 'capture'), patch.object(voice, 'transcribe', return_value='dictation'), patch.object(voice, 'rewrite', side_effect=voice.Cancelled):
                with self.assertRaises(voice.Cancelled):
                    voice.dictate('context', pathlib.Path(directory))
            self.assertFalse(any('wl-copy' in call.args[0] for call in run.call_args_list))

    def test_notification_does_not_swallow_cancellation(self):
        with patch.object(voice, 'run', side_effect=voice.Cancelled):
            with self.assertRaises(voice.Cancelled):
                voice.notify('Recording', 'test')

    def test_detached_clipboard_owner_does_not_hold_command_output_open(self):
        child = 'import os,time; pid=os.fork(); time.sleep(1) if pid == 0 else None; os._exit(0)'
        try:
            self.assertEqual(voice.run([sys.executable, '-c', child], discard=True, timeout=.3), '')
        except subprocess.TimeoutExpired:
            self.fail('Detached selection owner kept the controller output pipe open')


class Control(unittest.TestCase):
    """Second press must cancel a starting worker, not SIGKILL it."""

    def exercise(self, state, ready):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            runtime = pathlib.Path(directory, 'voice-dictation')
            runtime.mkdir()
            if ready:
                (runtime / 'ready').touch()
            def run(args, **kwargs):
                calls.append(args)
                return state if 'show' in args else ''
            with patch.dict(voice.os.environ, {'XDG_RUNTIME_DIR': directory}), patch.object(voice, 'run', side_effect=run):
                voice.control('plain')
            self.ready_left = (runtime / 'ready').exists()
        return calls

    def test_active_worker_with_ready_marker_gets_sigusr1(self):
        calls = self.exercise('active', ready=True)
        self.assertTrue(any('kill' in call and '--signal=SIGUSR1' in call for call in calls), calls)
        self.assertFalse(any('stop' in call for call in calls), calls)

    def test_active_worker_without_ready_marker_is_stopped(self):
        calls = self.exercise('active', ready=False)
        self.assertTrue(any('stop' in call for call in calls), calls)
        self.assertFalse(any('kill' in call for call in calls), calls)

    def test_activating_worker_is_stopped_before_it_can_die_on_the_signal(self):
        calls = self.exercise('activating', ready=True)
        self.assertTrue(any('stop' in call for call in calls), calls)
        self.assertFalse(any('kill' in call for call in calls), calls)

    def test_idle_start_clears_stale_ready_marker(self):
        calls = self.exercise('inactive', ready=True)
        self.assertTrue(any('start' in call for call in calls), calls)
        self.assertFalse(self.ready_left)

if __name__ == '__main__':
    unittest.main()
