import importlib.util
from pathlib import Path
import tempfile
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('adapter', Path(__file__).with_name('jev-agent.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
PROMPT = 'Review the code changes and return structured findings.\nUser intent supplied directly as an --intent argument\n-----BEGIN USER INTENT-----\nKeep permissions unchanged.\n-----END USER INTENT-----\n'

class Tests(unittest.TestCase):
    def test_advisory_does_not_replace_review(self):
        calls=[]
        result=m.augment(PROMPT, '.', lambda *a: {'status':'advisory','choice':'potential_contradiction','authority':'none'}, lambda *a:calls.append(a))
        self.assertTrue(result.startswith(PROMPT))
        self.assertIn('do not skip any review', result)
        self.assertEqual(len(calls),1)
        self.assertEqual(m.augment('run tests', '.', lambda *a:self.fail(), lambda *a:self.fail()), 'run tests')

    def test_invalid_response_is_not_authority(self):
        result=m.augment(PROMPT,'.',lambda *a:{'choice':'approve','authority':'captain'},lambda *a:None)
        self.assertIn('insufficient_evidence',result)
        self.assertNotIn('"approve"',result)

    def test_real_exec_preserves_exit_and_argv(self):
        with tempfile.TemporaryDirectory() as td:
            fake=Path(td)/'native'
            fake.write_text('#!/usr/bin/env python3\nimport sys\nprint("ARGS="+repr(sys.argv[1:]))\nprint(sys.stdin.read())\nsys.exit(7)\n');fake.chmod(0o755)
            launcher=Path(td)/'launch.py'
            launcher.write_text(f'import importlib.util,os,sys\ns=importlib.util.spec_from_file_location("x",{str(Path(__file__).with_name("jev-agent.py"))!r});m=importlib.util.module_from_spec(s);s.loader.exec_module(m)\nm.REAL["test"]={str(fake)!r}\nm.classify=lambda *a:{{"status":"advisory","choice":"appears_supported","authority":"none"}}\nm.record=lambda *a:None\nos.environ["NO_MISTAKES_GATE"]="1"\nsys.argv=["wrapper","test","--mode","json"]\nm.main()\n')
            p=subprocess.run(['python3',str(launcher)],input=PROMPT,text=True,capture_output=True)
            self.assertEqual(p.returncode,7,p.stderr)
            self.assertIn("ARGS=['--mode', 'json']",p.stdout)
            self.assertIn(PROMPT,p.stdout)
            self.assertIn('LOCAL JEV ADVISORY',p.stdout)

if __name__=='__main__':unittest.main()
