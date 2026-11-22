"""Synthetic wire checks: no real gateway, microphone or clipboard."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import json
import urllib.error

spec=importlib.util.spec_from_file_location('voice_http',Path(__file__).resolve().parents[2]/'modules/desktop/_voice_dictation.py')
voice=importlib.util.module_from_spec(spec);spec.loader.exec_module(voice)

class Wire(unittest.TestCase):
    def test_multipart_keeps_audio_and_disables_gateway_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            directory=Path(directory)
            (directory/'litellm-api-key').write_text('test-only-key')
            audio=directory/'audio.wav';audio.write_bytes(b'RIFF-test-audio')
            response=MagicMock();response.__enter__.return_value.read.return_value=b'{"text":"result"}'
            opener=MagicMock();opener.open.return_value=response
            with patch.dict(voice.os.environ,{'CREDENTIALS_DIRECTORY':str(directory)}),patch.object(voice.urllib.request,'build_opener',return_value=opener):
                self.assertEqual(voice.transcribe(audio),'result')
            req=opener.open.call_args.args[0]
            self.assertEqual(req.full_url,voice.GATEWAY+'/audio/transcriptions')
            self.assertIn(b'name="max_fallbacks"\r\n\r\n0\r\n',req.data)
            self.assertIn(b'RIFF-test-audio',req.data)
            self.assertNotIn(b'no-log',req.data)
            self.assertEqual(req.get_header('X-litellm-enable-message-redaction'),'true')
            self.assertEqual(req.get_header('X-litellm-num-retries'),'0')
            self.assertEqual(req.get_header('X-litellm-timeout'),'25')
            self.assertEqual(opener.open.call_args.kwargs['timeout'],30)

    def test_redirect_handler_refuses_credential_forwarding(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory,'litellm-api-key').write_text('test-only-key')
            with patch.dict(voice.os.environ,{'CREDENTIALS_DIRECTORY':directory}),patch.object(voice.urllib.request,'build_opener') as build:
                build.return_value.open.side_effect=urllib.error.URLError('offline')
                with self.assertRaises(urllib.error.URLError):voice.gateway('chat/completions',{})
            handlers=build.call_args.args
            self.assertEqual(handlers[0].proxies,{})
            self.assertIsNone(handlers[1].redirect_request(None,None,None,None,None,None))

if __name__=='__main__': unittest.main()
