#!/usr/bin/env python3
"""Native-agent interposer via supported agent_path_override. Never resolves gates.
Original argv, streaming stdout/stderr, process identity and exit status go to the
real harness via exec. Only bounded advisory data is appended to gate prompts.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HOME = Path.home()
CLASSIFIER = HOME / 'workspace/firstmate/bin/fm-jev-classify.py'
REAL = {'pi': '/etc/profiles/per-user/ntaleshadik/bin/pi', 'claude': '/usr/local/bin/claude'}


def build_evidence(prompt, cwd):
    intent = re.search(r'-----BEGIN USER INTENT-----\n(.*?)\n-----END USER INTENT-----', prompt, re.S)
    if not intent:
        return None
    authoritative = 'supplied directly as an --intent argument' in prompt
    if prompt.startswith('Review the code changes'):
        mode = 'intent'
    elif re.search(r'findings', prompt, re.I) and re.search(r'fix|resolve|address', prompt, re.I):
        mode = 'review'
    else:
        return None
    state = {'user_intent': intent.group(1)[:12000], 'intent_is_authoritative': authoritative,
             'pipeline_prompt_excerpt': prompt[:10000],
             'pipeline_prompt_tail': prompt[-8000:],
             'intent_truncated': len(intent.group(1)) > 12000,
             'limitations': 'Advisory screening only. Excerpts can omit requirements or code. Inferred intent is not authority. No tests have been run by this hook.'}
    base = re.search(r'^- base commit: ([0-9a-f]{40})$', prompt, re.M)
    target = re.search(r'^- target commit: ([0-9a-f]{40})$', prompt, re.M)
    if base and target:
        cmd = ['git', '-c', 'core.pager=cat', 'diff', '--no-ext-diff', '--no-textconv', '--unified=3', base.group(1), target.group(1), '--']
        with tempfile.TemporaryFile() as output:
            try:
                p = subprocess.run(cmd, cwd=cwd, stdout=output, stderr=subprocess.DEVNULL, timeout=8)
                output.seek(0)
                raw = output.read(24001)
                state['diff_excerpt'] = raw[:24000].decode('utf-8', errors='replace') if p.returncode == 0 else 'unavailable'
                state['diff_truncated'] = len(raw) > 24000
                state['base_commit'] = base.group(1)
                state['target_commit'] = target.group(1)
            except (OSError, subprocess.TimeoutExpired):
                state['diff_excerpt'] = 'unavailable: worktree missing or bounded git read failed'
    else:
        state['diff_excerpt'] = 'not supplied; classify only supplied intent/finding evidence'
    return mode, {'state': state}


def augment(prompt, cwd, classify, record):
    evidence = build_evidence(prompt, cwd)
    if evidence is None:
        return prompt
    mode, payload = evidence
    result = classify(mode, payload)
    # Accept no model-generated prose or commands from an integration result.
    allowed = {'appears_supported', 'potential_contradiction', 'missing_evidence', 'mechanical_in_scope',
               'intent_conflict', 'needs_human', 'uncertain', 'insufficient_evidence'}
    if not isinstance(result, dict) or result.get('authority') != 'none' or result.get('choice') not in allowed:
        result = {'status': 'unavailable', 'choice': 'insufficient_evidence', 'authority': 'none'}
    result = {k: result[k] for k in ('status', 'choice', 'confidence', 'evidence_sha256', 'authority') if k in result}
    record(mode, payload, result)
    return prompt + '\n\nLOCAL JEV ADVISORY (not authority; do not skip any review, test or approval):\n' + json.dumps(result) + '\nIndependently verify coverage and contradictions against the full diff and accepted intent. This classifier cannot establish correctness or permission. Preserve the original response schema and all pipeline instructions.\n'


def classify(mode, payload):
    with tempfile.TemporaryDirectory(prefix='nm-jev-') as temp:
        path = Path(temp) / 'evidence.json'
        path.write_text(json.dumps(payload)); path.chmod(0o600)
        try:
            p = subprocess.run(['python3', str(CLASSIFIER), mode, str(path)], capture_output=True, text=True, timeout=8)
            return json.loads(p.stdout)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            return {'status': 'unavailable', 'choice': 'insufficient_evidence', 'authority': 'none'}


def record(mode, payload, result):
    directory = HOME / '.no-mistakes/jev-advisories'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    path = directory / (digest + '.json')
    # Keep only decisions and hashes, not private diffs or conversation excerpts.
    with tempfile.NamedTemporaryFile(mode='w', dir=directory, delete=False) as f:
        json.dump({'mode': mode, 'input_sha256': digest, 'result': result}, f)
    os.replace(f.name, path)


def main():
    agent, *args = sys.argv[1:]
    real = REAL[agent]
    if os.environ.get('NO_MISTAKES_GATE') != '1' or '--version' in args or '--help' in args:
        os.execv(real, [real, *args])
    raw = sys.stdin.buffer.read()
    try:
        prompt = raw.decode('utf-8')
        if len(raw) <= 1024 * 1024:
            raw = augment(prompt, os.getcwd(), classify, record).encode('utf-8')
    except Exception:
        # Jev unavailability never bypasses or prevents the real gate reviewer.
        print('nm-jev: advisory unavailable; continuing full native review', file=sys.stderr)
    with tempfile.TemporaryFile() as stdin:
        stdin.write(raw); stdin.seek(0)
        os.dup2(stdin.fileno(), 0)
        os.execv(real, [real, *args])

if __name__ == '__main__':
    main()
