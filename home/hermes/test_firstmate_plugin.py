import asyncio
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

s=importlib.util.spec_from_file_location('plugin',Path(__file__).parent/'firstmate-relay/__init__.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)

class Tests(unittest.IsolatedAsyncioTestCase):
    async def test_busy_gateway_uses_authenticated_ingress_not_model(self):
        hooks={};commands={};sent=[];auth=[];ssh=[]
        ctx=SimpleNamespace(register_command=lambda name,fn,*a,**k:commands.update({name:fn}), register_hook=lambda name,fn:hooks.update({name:fn}))
        m.register(ctx)
        async def send(chat,text):sent.append((chat,text))
        gateway=SimpleNamespace(_is_user_authorized_for_source=lambda source:auth.append(source.user_id) or source.user_id=='42', _adapter_for_source=lambda source:SimpleNamespace(send=send), running=True)
        source=SimpleNamespace(platform=SimpleNamespace(value='telegram'),user_id='42',chat_id='42',chat_type='dm')
        event=SimpleNamespace(source=source,get_command=lambda:'fmstatus',get_command_args=lambda:'')
        async def create(*args,**kwargs):
            ssh.append(args)
            async def communicate(envelope):return b'Live status, without a model',b''
            return SimpleNamespace(returncode=0,communicate=communicate)
        with patch.dict('os.environ',{'TELEGRAM_ALLOWED_USERS':'42'}),patch('asyncio.create_subprocess_exec',create):
            result=hooks['pre_gateway_dispatch'](event=event,gateway=gateway)
            self.assertEqual(result['action'],'skip')
            await asyncio.gather(*list(m._pending))
        self.assertEqual(auth,['42']);self.assertEqual(len(ssh),1)
        self.assertEqual(sent,[('42','Live status, without a model')])
        source.user_id='43'
        self.assertIsNone(hooks['pre_gateway_dispatch'](event=event,gateway=gateway))
        self.assertEqual(len(ssh),1)

if __name__=='__main__':unittest.main()
