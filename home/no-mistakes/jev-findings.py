#!/usr/bin/env python3
"""Read-only no-mistakes round observer. Advisory triage, never a gate decision.
Runs separately from the daemon so active pipelines need no restart. No write
connection to no-mistakes state, no agent decision, no git mutation or publish.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location('jev_agent', Path(__file__).with_name('jev-agent.py'))
adapter = importlib.util.module_from_spec(spec); spec.loader.exec_module(adapter)
ROOT = Path.home() / '.no-mistakes'


def rounds(database, since):
    with sqlite3.connect('file:' + str(database) + '?mode=ro', uri=True, timeout=5) as db:
        db.row_factory = sqlite3.Row
        return list(db.execute('''SELECT r.id run_id,r.intent,r.intent_source,r.base_sha,r.worktree_dir,
            q.id round_id,q.reviewed_head_sha,q.findings_json,q.created_at
            FROM step_rounds q JOIN step_results s ON s.id=q.step_result_id JOIN runs r ON r.id=s.run_id
            WHERE s.step_name='review' AND q.created_at>=? AND q.findings_json IS NOT NULL
            ORDER BY q.created_at DESC LIMIT 100''', (since,)))


def evidence(row, finding):
    prompt = ('Review the code changes\n- base commit: ' + (row['base_sha'] or '') +
        '\n- target commit: ' + (row['reviewed_head_sha'] or '') + '\n' +
        ('supplied directly as an --intent argument\n' if row['intent_source']=='agent' else 'inferred intent\n') +
        '-----BEGIN USER INTENT-----\n' + (row['intent'] or '(No accepted intent recorded; do not infer it.)') +
        '\n-----END USER INTENT-----\n')
    data = adapter.build_evidence(prompt, row['worktree_dir'] or '.')
    state = data[1]['state']
    state.pop('pipeline_prompt_excerpt', None)
    state.pop('pipeline_prompt_tail', None)
    encoded = json.dumps(finding)
    state['review_finding'] = finding if len(encoded) <= 12000 else {'truncated_excerpt': encoded[:12000]}
    state['finding_truncated'] = len(encoded) > 12000
    state['reviewed_head_sha'] = row['reviewed_head_sha']
    state['limitations'] += ' A review finding is a claim, not a reproduced failure. The pipeline retains all authority.'
    return {'state':state}


def observe(database, directory, classify=adapter.classify, now=None, probe=False):
    now = int(time.time()) if now is None else now
    directory = Path(directory); directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with sqlite3.connect(directory/'observer.sqlite', timeout=5) as ledger:
        ledger.execute('CREATE TABLE IF NOT EXISTS meta(enabled_at INTEGER NOT NULL)')
        ledger.execute('CREATE TABLE IF NOT EXISTS decisions(digest TEXT PRIMARY KEY, run_id TEXT, round_id TEXT, attempts INTEGER, retry_at INTEGER, result TEXT)')
        if not ledger.execute('SELECT 1 FROM meta').fetchone():
            ledger.execute('INSERT INTO meta VALUES(?)',(now,));ledger.commit()
        since = 0 if probe else ledger.execute('SELECT enabled_at FROM meta').fetchone()[0]
        count = 0
        for row in rounds(database,since):
            findings=json.loads(row['findings_json']).get('findings',[])
            if not isinstance(findings,list):continue
            for finding in findings:
                if not isinstance(finding,dict):continue
                digest=hashlib.sha256(json.dumps([row['run_id'],row['round_id'],row['intent'],finding],sort_keys=True).encode()).hexdigest()
                prior=ledger.execute('SELECT attempts,retry_at,result FROM decisions WHERE digest=?',(digest,)).fetchone()
                if prior and (prior[0]>=3 or prior[1]>now or (prior[2] and json.loads(prior[2]).get('status')=='advisory')):continue
                attempts=(prior[0] if prior else 0)+1
                # Bound retry and survive process interruption without hot-looping.
                ledger.execute('INSERT OR REPLACE INTO decisions VALUES(?,?,?,?,?,?)',(digest,row['run_id'],row['round_id'],attempts,now+120,None));ledger.commit()
                payload=evidence(row,finding)
                result=classify('review',payload)
                ledger.execute('UPDATE decisions SET result=? WHERE digest=?',(json.dumps(result),digest));ledger.commit()
                artifact={'run_id':row['run_id'],'round_id':row['round_id'],'finding_id':finding.get('id'),
                    'finding_sha256':digest,'reviewed_head_sha':row['reviewed_head_sha'],
                    'advisory':result,'authority':'none','pipeline_unchanged':True}
                with tempfile.NamedTemporaryFile(mode='w',dir=directory,delete=False) as out:
                    json.dump(artifact,out,indent=2)
                os.replace(out.name,directory/(digest+'.json'))
                print(json.dumps(artifact))
                count+=1
                if count >= (1 if probe else 4):return count
        return count


def main():
    os.umask(0o077)
    directory=ROOT/'jev-findings'
    if sys.argv[1:] and sys.argv[1]=='status':
        run_id=sys.argv[2] if len(sys.argv)>2 else None
        for p in sorted(directory.glob('*.json')):
            data=json.loads(p.read_text())
            if not run_id or data['run_id']==run_id:print(json.dumps(data))
    else:
        observe(ROOT/'state.sqlite',directory,probe=sys.argv[1:]==['--probe-latest'])

if __name__=='__main__':main()
