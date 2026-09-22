#!/usr/bin/env python3
"""Model-free captain-hold escalation and authenticated command reply intake.
One Telegram receiver remains Hermes. This service only sends via Bot API and
receives authenticated command envelopes from the default-profile Hermes hook.
"""
import csv
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time
import urllib.request
import uuid

HOME = Path.home() / 'workspace/firstmate'
SECRETS = Path.home() / '.config/sops-nix/secrets'


def run(home, script, *args, text=None):
    p = subprocess.run([str(home / 'bin' / script), *args], cwd=home,
        env=dict(os.environ, FM_HOME=str(home), PATH=str(Path.home() / '.npm-global/bin') + ':' + str(Path.home() / '.local/bin') + ':' + os.environ.get('PATH', '/usr/bin:/bin')), input=text, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)
    if p.returncode:
        raise RuntimeError('Firstmate command failed: ' + script)
    return p.stdout


def field(record, key):
    match = re.search(r'^  ' + re.escape(key) + r': (.*)$', record, re.M)
    if not match:
        return ''
    value = match.group(1)
    if value.startswith('"'):
        return json.loads(value)
    return value


def current_hold(home, task):
    record = run(home, 'fm-tasks-axi.sh', 'show', task, '--full')
    if field(record, 'hold_kind') != 'captain' or field(record, 'held') != 'yes' or field(record, 'state') == 'done':
        return None
    until = field(record, 'hold_until')
    if until and until != '-' and until > dt.datetime.now(dt.timezone.utc).date().isoformat():
        return None
    body = field(record, 'body')
    stamp = re.match(r'Captain hold set: (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)', body)
    if not stamp:
        return None
    occurrence = body.count('Resolution recorded by fm-captain-hold.')
    identity = stamp.group(1) + ':' + str(occurrence)
    since = dt.datetime.strptime(stamp.group(1), '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=dt.timezone.utc).timestamp()
    return {'task': task, 'identity': identity, 'since': since,
            'title': field(record, 'title'), 'question': field(record, 'hold_reason')}


class Relay:
    def __init__(self, db, home, allowed, hold=current_hold, enqueue=None, send=None):
        self.home, self.allowed, self.hold = Path(home), set(allowed), hold
        Path(db).parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.db = sqlite3.connect(db, timeout=30, isolation_level=None)
        os.chmod(db, 0o600)
        self.db.execute('CREATE TABLE IF NOT EXISTS calls(token TEXT PRIMARY KEY, task TEXT, identity TEXT, question TEXT, sent INTEGER DEFAULT 0, answer TEXT, receipt TEXT, UNIQUE(task,identity))')
        self.enqueue = enqueue or self._enqueue
        self.send = send

    def _enqueue(self, marker, text):
        # Crash after enqueue but before SQLite commit: find the same marker in
        # pending OR handled inbox records before retrying. No shell interpolation.
        inbox = self.home / 'state/inbox'
        for folder in (inbox, inbox / 'handled'):
            if folder.exists():
                for p in folder.iterdir():
                    if p.is_file() and not p.is_symlink() and p.stat().st_size <= 100000:
                        if marker in p.read_text(errors='replace'):
                            return 'already queued'
        return run(self.home, 'fm-inbox.sh', 'note', '-', text=text)

    def tick(self, holds, now=None):
        now = time.time() if now is None else now
        sent = 0
        for h in holds:
            if now - h['since'] < 600:
                continue
            # Persist correlation BEFORE the network call. A timed-out send may
            # have reached Telegram; every retry must retain the same code.
            self.db.execute('INSERT OR IGNORE INTO calls(token,task,identity,question) VALUES(?,?,?,?)',
                (uuid.uuid4().hex[:16], h['task'], h['identity'], h['question']))
            self.db.execute('BEGIN IMMEDIATE')
            try:
                row = self.db.execute('SELECT token,sent,answer FROM calls WHERE task=? AND identity=?', (h['task'],h['identity'])).fetchone()
                if not row[1] and row[2] is None:
                    # Recheck at send time so locally answered/changed calls cancel.
                    live = self.hold(self.home, h['task'])
                    if live and live['identity'] == h['identity']:
                        message = ('Captain, Firstmate needs your input:\n\n' + h['title'][:350] + '\n' + h['question'][:2600] +
                                   '\n\nReply without any model using:\n/fmreply ' + row[0] + ' your answer\n\n/fmstatus for status')
                        self.send(message)
                        self.db.execute('UPDATE calls SET sent=1 WHERE token=?', (row[0],))
                        sent += 1
                self.db.execute('COMMIT')
            except Exception:
                self.db.execute('ROLLBACK')
                raise
        return sent

    def receive(self, event):
        if event.get('platform') != 'telegram' or str(event.get('user_id')) not in self.allowed:
            raise ValueError('Unauthorized relay source')
        command = event.get('command')
        args = event.get('args', '')
        if not isinstance(args, str) or len(args.encode()) > 8192:
            raise ValueError('Reply too large')
        if command == 'fmstatus':
            return run(self.home, 'fm-inbox.sh', 'status')[:3800]
        if command != 'fmreply':
            raise ValueError('Unknown relay command')
        parts = args.strip().split(None, 1)
        if len(parts) != 2 or not re.fullmatch('[0-9a-f]{16}', parts[0]) or not parts[1].strip():
            return 'Use /fmreply <question code> <your answer> from the escalation message.'
        token, answer = parts
        self.db.execute('BEGIN IMMEDIATE')
        try:
            row = self.db.execute('SELECT task,identity,answer,receipt FROM calls WHERE token=?', (token,)).fetchone()
            if row is None:
                reply = 'Unknown question code; use the code from the latest escalation.'
            elif row[2] is not None:
                reply = 'Your answer is already queued.' if row[2] == answer else 'This question already has a queued answer; send further feedback to Firstmate directly.'
            else:
                live = self.hold(self.home, row[0])
                if not live or live['identity'] != row[1]:
                    reply = 'That question was resolved or replaced locally. No stale answer was applied.'
                else:
                    marker = '[telegram-relay:' + token + ']'
                    text = marker + ' [via telegram] Captain feedback for task ' + row[0] + ' (hold ' + row[1] + '):\n' + answer
                    receipt = self.enqueue(marker, text)
                    self.db.execute('UPDATE calls SET answer=?,receipt=? WHERE token=?', (answer,receipt,token))
                    reply = 'Queued your exact answer for the current Firstmate session. Delivery does not itself approve or close the task.'
            self.db.execute('COMMIT')
            return reply
        except Exception:
            self.db.execute('ROLLBACK')
            raise


def allowed_users():
    return [x.strip() for x in (SECRETS / 'telegram_allowed_users').read_text().split(',') if x.strip().isdigit()]


def sender(text):
    users = allowed_users()
    if not users:
        raise ValueError('No allowed Telegram user')
    token = (SECRETS / 'telegram_bot_token').read_text().strip()
    req = urllib.request.Request('https://api.telegram.org/bot' + token + '/sendMessage',
        data=json.dumps({'chat_id': users[0], 'text': text, 'disable_web_page_preview': True}).encode(),
        headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req, timeout=15) as response:
        result = json.load(response)
    if not result.get('ok'):
        raise RuntimeError('Telegram did not accept notification')


def holds():
    text = run(HOME, 'fm-tasks-axi.sh', 'list', '--state', 'held', '--fields', 'hold_kind')
    result=[]
    for line in text.splitlines():
        if re.match(r'^  [A-Za-z0-9._-]+,', line):
            task = next(csv.reader([line.strip()]))[0]
            h = current_hold(HOME, task)
            if h:
                result.append(h)
    return result


def main():
    os.umask(0o077)
    relay = Relay(HOME / 'state/telegram-relay/relay.sqlite', HOME, allowed_users(), send=sender)
    if sys.argv[1:] == ['receive']:
        try:
            raw = sys.stdin.buffer.read(16385)
            if len(raw) > 16384:
                raise ValueError('Envelope too large')
            print(relay.receive(json.loads(raw)))
        except Exception as exc:
            print('Relay could not accept this message (' + type(exc).__name__ + '). Nothing was approved. Retry with the same question code.')
            return 1
    elif sys.argv[1:] == ['tick']:
        print('Notifications accepted:', relay.tick(holds()))
    else:
        raise ValueError('Use tick or receive')
    return 0

if __name__ == '__main__':
    sys.exit(main())
