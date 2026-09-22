import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('relay',Path(__file__).with_name('fm-telegram-relay.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class Tests(unittest.TestCase):
    def test_timer_reply_dedup_restart_and_stale(self):
        with tempfile.TemporaryDirectory() as td:
            sent=[];queued=[]
            h={'task':'task-1','identity':'stamp:0','since':100,'title':'Choose','question':'Light or dark?'}
            live=[h]
            def hold(*args):return live[0]
            def queue(*args):queued.append(args);return 'receipt'
            path=Path(td)/'db'
            relay=m.Relay(path,td,['42'],hold=hold,enqueue=queue,send=sent.append)
            self.assertEqual(relay.tick([h],699),0)
            self.assertEqual(relay.tick([h],700),1)
            self.assertEqual(relay.tick([h],701),0)
            relay.db.close()
            relay=m.Relay(path,td,['42'],hold=hold,enqueue=queue,send=sent.append)
            token=relay.db.execute('SELECT token FROM calls').fetchone()[0]
            event={'platform':'telegram','user_id':'42','command':'fmreply','args':token+' keep both; $(touch /tmp/not-executed)'}
            self.assertIn('Queued',relay.receive(event));self.assertIn('already queued',relay.receive(event))
            self.assertEqual(len(queued),1);self.assertIn('$(touch',queued[0][1])
            with self.assertRaises(ValueError):relay.receive(dict(event,user_id='43'))
            with self.assertRaises(ValueError):relay.receive(dict(event,platform='mattermost'))
            h2=dict(h,identity='stamp:1');live[0]=h2
            relay.tick([h2],800)
            token2=relay.db.execute('SELECT token FROM calls WHERE identity=?',('stamp:1',)).fetchone()[0]
            live[0]=None
            self.assertIn('resolved or replaced',relay.receive(dict(event,args=token2+' yes')))
            self.assertEqual(len(queued),1)

    def test_send_failure_retries_and_local_answer_cancels(self):
        with tempfile.TemporaryDirectory() as td:
            h={'task':'t','identity':'one','since':0,'title':'t','question':'q'}
            live=[h];attempts=[]
            def send(text):
                attempts.append(text)
                if len(attempts)==1:raise OSError('offline')
            relay=m.Relay(Path(td)/'db',td,['42'],hold=lambda *a:live[0],send=send)
            with self.assertRaises(OSError):relay.tick([h],600)
            self.assertEqual(relay.tick([h],601),1)
            self.assertEqual(attempts[0],attempts[1], 'uncertain send must retain the same reply code')
            h2=dict(h,identity='two');live[0]=None
            self.assertEqual(relay.tick([h2],700),0)

    def test_actual_tasks_axi_held_projection(self):
        record = '  state: queued\n  held: yes\n  hold_kind: captain\n  hold_until: "-"\n  body: "Captain hold set: 2026-09-19T02:59:39Z\\n\\nQuestion"\n  hold_reason: "Which?"\n  title: Decision\n'
        with patch.object(m, 'run', return_value=record):
            self.assertEqual(m.current_hold(Path('/unused'), 't')['question'], 'Which?')
        with patch.object(m, 'run', return_value=record.replace('held: yes', 'held: no')):
            self.assertIsNone(m.current_hold(Path('/unused'), 't'))

    def test_show_parser_decodes_text(self):
        self.assertEqual(m.field('  hold_reason: "one\\ntwo"\n','hold_reason'),'one\ntwo')
        self.assertEqual(m.field('  state: queued\n','state'),'queued')

if __name__=='__main__':unittest.main()
