import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

s=importlib.util.spec_from_file_location('observer',Path(__file__).with_name('jev-findings.py'))
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

class Tests(unittest.TestCase):
    def test_automatic_triage_read_only_and_deduplicated(self):
        with tempfile.TemporaryDirectory() as td:
            db=Path(td)/'pipeline.sqlite'
            c=sqlite3.connect(db)
            c.executescript('CREATE TABLE runs(id, intent, intent_source, base_sha, worktree_dir); CREATE TABLE step_results(id,run_id,step_name); CREATE TABLE step_rounds(id,step_result_id,reviewed_head_sha,findings_json,created_at);')
            c.execute('INSERT INTO runs VALUES(?,?,?,?,?)',('run','Do not remove approvals','agent','a'*40,td))
            c.execute('INSERT INTO step_results VALUES(?,?,?)',('step','run','review'))
            c.execute('INSERT INTO step_rounds VALUES(?,?,?,?,?)',('round','step','b'*40,json.dumps({'findings':[{'id':'r1','description':'Remove the approval step'}]}),100))
            c.commit();c.close()
            before=hashlib.sha256(db.read_bytes()).hexdigest();calls=[]
            def classify(mode,payload):
                calls.append((mode,payload))
                return {'status':'advisory','choice':'intent_conflict','authority':'none'}
            self.assertEqual(m.observe(db,Path(td)/'results',classify,100),1)
            self.assertEqual(m.observe(db,Path(td)/'results',classify,101),0)
            self.assertEqual(len(calls),1)
            self.assertEqual(calls[0][1]['state']['user_intent'],'Do not remove approvals')
            self.assertEqual(calls[0][1]['state']['review_finding']['id'],'r1')
            self.assertEqual(hashlib.sha256(db.read_bytes()).hexdigest(),before)
            artifacts=list((Path(td)/'results').glob('*.json'));self.assertEqual(len(artifacts),1)
            self.assertTrue(json.loads(artifacts[0].read_text())['pipeline_unchanged'])

if __name__=='__main__':unittest.main()
