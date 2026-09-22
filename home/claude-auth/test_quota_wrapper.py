import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class QuotaWrapperTest(unittest.TestCase):
    def test_removes_only_service_override_and_forwards_arguments(self):
        wrapper = Path(__file__).with_name('quota-axi')
        with tempfile.TemporaryDirectory() as tmp:
            cli = Path(tmp) / '.npm-global/bin/quota-axi'
            cli.parent.mkdir(parents=True)
            cli.write_text('#!/usr/bin/env python3\n'
                           'import json,os,sys\n'
                           'print(json.dumps({"override": "CLAUDE_CODE_OAUTH_TOKEN" in os.environ, '
                           '"codex": os.environ.get("CODEX_HOME"), "args": sys.argv[1:]}))\n')
            cli.chmod(0o700)
            env = dict(os.environ, HOME=tmp, CLAUDE_CODE_OAUTH_TOKEN='test-only', CODEX_HOME='/test/codex')
            for args in [['--provider', 'claude', '--full', '--json'], ['update'], ['--tui', '--once']]:
                result = subprocess.run([str(wrapper), *args], env=env, text=True, capture_output=True, check=True)
                self.assertEqual(json.loads(result.stdout), {'override': False, 'codex': '/test/codex', 'args': args})

    def test_preserves_vendor_exit_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            cli = Path(tmp) / '.npm-global/bin/quota-axi'
            cli.parent.mkdir(parents=True)
            cli.write_text('#!/bin/sh\nexit 23\n')
            cli.chmod(0o700)
            result = subprocess.run([str(Path(__file__).with_name('quota-axi'))], env=dict(os.environ, HOME=tmp))
            self.assertEqual(result.returncode, 23)


if __name__ == '__main__':
    unittest.main()
