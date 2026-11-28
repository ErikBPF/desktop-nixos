"""Routing boundaries: one primary attempt, bounded local fallback, no data loss."""
import importlib.util
import http.client
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import urllib.error
import wave

spec = importlib.util.spec_from_file_location('gateway_voice', Path(__file__).resolve().parents[2] / 'modules/desktop/_voice_dictation.py')
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


class Gateway(unittest.TestCase):
    def test_primary_rewrite_binds_context_and_never_calls_local(self):
        # Public operation exists in the first slice; this fails on local-only routing.
        calls = []
        def request(_opener, req, **kwargs):
            calls.append(req)
            class Response:
                def __enter__(self): return self
                def __exit__(self, *_): pass
                def read(self, *args):
                    if '/api/chat' in req.full_url:
                        return b'{"done":true,"done_reason":"stop","message":{"content":"local"}}'
                    return b'{"choices":[{"finish_reason":"stop","message":{"content":"gateway"}}]}'
            return Response()
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, 'litellm-api-key').write_text('test-only-key')
            with patch.dict(voice.os.environ, {'CREDENTIALS_DIRECTORY': directory}), patch.object(voice.urllib.request.OpenerDirector, 'open', request):
                self.assertEqual(voice.rewrite('ditado', 'contexto'), 'gateway')
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0].full_url, 'https://litellm.homelab.pastelariadev.com/v1/chat/completions')
        body = json.loads(calls[0].data)
        self.assertEqual(body['model'], 'qwen3.8-flash-next')
        self.assertEqual(json.loads(body['messages'][1]['content']), {'dictation': 'ditado', 'copied_context': 'contexto'})
        self.assertEqual(calls[0].get_header('X-litellm-enable-message-redaction'), 'true')
        self.assertEqual(body['fallbacks'], [])
        self.assertEqual(body['max_fallbacks'], 0)

    def test_asr_unavailable_reuses_same_file_once(self):
        with patch.object(voice, 'gateway', side_effect=urllib.error.URLError('offline'), create=True) as primary, patch.object(voice, 'local_transcribe', return_value='ditado', create=True) as local, patch.object(voice, 'notify'):
            self.assertTrue(hasattr(voice, 'transcribe'), 'ASR router must retain audio for fallback')
            path = Path('/private/capture.wav')
            self.assertEqual(voice.transcribe(path), 'ditado')
            local.assert_called_once_with(path)
            primary.assert_called_once()

    def test_cancel_never_runs_fallback(self):
        with patch.object(voice, 'gateway', side_effect=voice.Cancelled, create=True), patch.object(voice, 'local_transcribe', create=True) as local:
            self.assertTrue(hasattr(voice, 'transcribe'), 'ASR router missing')
            with self.assertRaises(voice.Cancelled): voice.transcribe(Path('capture.wav'))
            local.assert_not_called()

    def test_successful_silence_never_runs_fallback(self):
        with patch.object(voice, 'gateway', return_value={'text': ' '}, create=True), patch.object(voice, 'local_transcribe', create=True) as local:
            self.assertTrue(hasattr(voice, 'transcribe'), 'ASR router missing')
            with self.assertRaisesRegex(RuntimeError, 'No speech'): voice.transcribe(Path('capture.wav'))
            local.assert_not_called()

    def test_auth_failure_is_visible_and_falls_back_locally(self):
        error = urllib.error.HTTPError('https://gateway', 401, 'denied', {}, None)
        self.addCleanup(error.close)
        with patch.object(voice, 'gateway', side_effect=error, create=True), patch.object(voice, 'local_transcribe', return_value='local', create=True), patch.object(voice, 'notify') as notice:
            self.assertTrue(hasattr(voice, 'transcribe'), 'ASR router missing')
            self.assertEqual(voice.transcribe(Path('capture.wav')), 'local')
            self.assertIn('credential', ' '.join(str(x) for x in notice.call_args.args).lower())

    def test_cli_diagnostics_never_become_clipboard_text(self):
        self.assertTrue(hasattr(voice, 'local_transcribe'), 'Pinned CLI fallback missing')
        preamble = 'Loading audio file: "capture.wav"\nAudio format: 16000 Hz, 1 channel(s), Int\nProcessing 16000 samples (1.00s)...\n'
        with patch.object(voice, 'run', return_value=preamble + '\nlinha um\nlinha dois'):
            self.assertEqual(voice.local_transcribe(Path('capture.wav')), 'linha um\nlinha dois')
        for output in (preamble, 'unexpected diagnostic\n\nnot transcript', preamble + 'Error: model failed to load', preamble + 'No speech detected, skipping transcription.'):
            with self.subTest(output=output), patch.object(voice, 'run', return_value=output):
                with self.assertRaises(RuntimeError): voice.local_transcribe(Path('capture.wav'))

    def test_local_transcribe_tolerates_extra_banner_diagnostics(self):
        # A warning before the banner used to discard a valid transcript. Only
        # the Processing marker and the following transcript are contractual.
        output = ('warning: runtime state already exists\n'
                  + 'Loading audio file: "/tmp/capture.wav"\n'
                  + 'Audio format: 16000 Hz, 1 channel(s), Int\n'
                  + 'Processing 16000 samples (1.00s)...\n'
                  + 'VAD: 0.90s speech (90.0% of audio)\n\n'
                  + 'texto final')
        with patch.object(voice, 'run', return_value=output):
            self.assertEqual(voice.local_transcribe(Path('capture.wav')), 'texto final')

class FailureBoundaries(unittest.TestCase):
    def test_malformed_primary_rewrite_uses_local(self):
        for result in ({'choices': [{'finish_reason': 'stop', 'message': {'content': None}}]}, {'choices': []}, {'choices': [{'finish_reason': 'length', 'message': {'content': 'partial'}}]}):
            with self.subTest(result=result), patch.object(voice, 'gateway', return_value=result), patch.object(voice, 'local_rewrite', return_value='local') as local, patch.object(voice, 'notify'):
                self.assertEqual(voice.rewrite('dictation', 'context'), 'local')
                local.assert_called_once()

    def test_incomplete_transport_reads_use_local_fallback(self):
        with patch.object(voice, 'gateway', side_effect=http.client.IncompleteRead(b'partial')), patch.object(voice, 'local_transcribe', return_value='local') as asr, patch.object(voice, 'local_rewrite', return_value='local') as rewrite, patch.object(voice, 'notify'):
            self.assertEqual(voice.transcribe(Path('audio')), 'local')
            self.assertEqual(voice.rewrite('dictation', 'context'), 'local')
            asr.assert_called_once()
            rewrite.assert_called_once()

    def test_malformed_asr_falls_back_once(self):
        for result in ({}, {'text': None}, {'text': 42}):
            with self.subTest(result=result), patch.object(voice, 'gateway', return_value=result), patch.object(voice, 'local_transcribe', return_value='local') as local, patch.object(voice, 'notify'):
                self.assertEqual(voice.transcribe(Path('audio')), 'local')
                local.assert_called_once()

    def test_asr_primary_bypasses_local(self):
        with patch.object(voice, 'gateway', return_value={'text': 'transcript'}), patch.object(voice, 'local_transcribe') as local:
            self.assertEqual(voice.transcribe(Path('audio')), 'transcript')
            local.assert_not_called()

    def test_failure_or_cancel_at_each_boundary_preserves_clipboard_and_removes_audio(self):
        for boundary in ('capture', 'transcribe', 'rewrite'):
            for error in (RuntimeError('unavailable'), voice.Cancelled()):
                with self.subTest(boundary=boundary, error=type(error)), tempfile.TemporaryDirectory() as directory:
                    audio = Path(directory) / 'capture.wav'
                    audio.write_bytes(b'private')
                    with patch.object(voice, 'capture', side_effect=error if boundary == 'capture' else None), patch.object(voice, 'transcribe', return_value='text', side_effect=error if boundary == 'transcribe' else None), patch.object(voice, 'rewrite', return_value='text', side_effect=error if boundary == 'rewrite' else None), patch.object(voice, 'run', return_value='copied') as commands, patch.object(voice, 'notify'):
                        with self.assertRaises(type(error)): voice.dictate('context', Path(directory))
                    self.assertFalse(audio.exists())
                    self.assertFalse(any('wl-copy' in c.args[0] for c in commands.call_args_list))

class Capture(unittest.TestCase):
    def test_recording_wait_keeps_the_duration_limit(self):
        process = MagicMock()
        process.poll.return_value = None
        with patch.object(voice.time, 'monotonic', side_effect=[0, 114.9, 115.1]), patch.object(voice.STOP, 'wait', return_value=False) as wait:
            voice.wait_for_stop(process)
        self.assertEqual(wait.call_count, 1)
        self.assertGreater(wait.call_args.args[0], 0)
        self.assertLessEqual(wait.call_args.args[0], .2)
        process.poll.assert_called_once()

    def test_recorder_death_fails_promptly_reaps_and_preserves_clipboard(self):
        process = MagicMock()
        process.poll.side_effect = [None, 7, 7]
        def bounded_wait(seconds):
            self.assertLessEqual(seconds, .2, 'Recorder death must not wait for the capture deadline')
            return False
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / 'capture.wav'
            audio.write_bytes(b'partial private audio')
            with patch.object(voice.subprocess, 'Popen', return_value=process), patch.object(voice.time, 'sleep'), patch.object(voice.STOP, 'wait', side_effect=bounded_wait), patch.object(voice, 'notify'), patch.object(voice, 'run') as commands, patch.object(voice, 'transcribe') as transcribe:
                with self.assertRaisesRegex(RuntimeError, 'Recorder exited'):
                    voice.dictate('plain', Path(directory))
            process.wait.assert_called_once_with(timeout=3)
            process.send_signal.assert_not_called()
            transcribe.assert_not_called()
            commands.assert_not_called()
            self.assertFalse(audio.exists())

    def test_capture_closes_wav_before_transcribing(self):
        self.assertTrue(hasattr(voice, 'capture'), 'Capture must retain WAV for both backends')
        events = []
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / 'capture.wav'
            def launch(args, **kwargs):
                events.append('capture')
                with wave.open(str(audio), 'wb') as wav:
                    wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                    wav.writeframes(b'\x00\x01' * 1600)
                process = MagicMock()
                process.wait.side_effect = lambda **kw: events.append('reaped') or 1
                process.returncode = 1
                process.poll.return_value = None
                return process
            def transcribe(path):
                self.assertIn('reaped', events)
                self.assertEqual(path, audio)
                return 'voice result'
            with patch.object(voice.subprocess, 'Popen', side_effect=launch), patch.object(voice, 'run', return_value='idle') as commands, patch.object(voice, 'wait_for_stop'), patch.object(voice, 'transcribe', side_effect=transcribe), patch.object(voice, 'notify'):
                voice.dictate('plain', Path(directory))
            self.assertIn('capture', events, 'Capture must retain WAV for both backends')
            self.assertEqual([c.kwargs['input'] for c in commands.call_args_list if 'wl-copy' in c.args[0]], ['voice result'])

    def test_cancel_reaps_recorder_without_transcription(self):
        self.assertTrue(hasattr(voice, 'capture'), 'Capture must reap recorder on cancellation')
        with tempfile.TemporaryDirectory() as directory:
            process = MagicMock()
            process.poll.return_value = None
            with patch.object(voice.subprocess, 'Popen', return_value=process), patch.object(voice, 'run', return_value='idle'), patch.object(voice, 'wait_for_stop', side_effect=voice.Cancelled), patch.object(voice, 'transcribe') as transcribe, patch.object(voice, 'notify'):
                with self.assertRaises(voice.Cancelled): voice.dictate('plain', Path(directory))
            self.assertTrue(process.wait.called, 'Cancelled capture must reap recorder')
            transcribe.assert_not_called()

if __name__ == '__main__': unittest.main()
