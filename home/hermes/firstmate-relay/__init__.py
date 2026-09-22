import asyncio
import importlib.util
from pathlib import Path

_pending = set()


def register(ctx):
    # The gateway hook handles these before running-agent/model dispatch. The
    # command fallback never invokes a model or silently drops an answer.
    def unavailable(args):
        return 'Firstmate relay is unavailable. Your answer was not sent; please retry later.'
    ctx.register_command('fmreply', unavailable, 'Answer a Firstmate question without a model', args_hint='<code> <answer>')
    ctx.register_command('fmstatus', unavailable, 'Read Firstmate status without a model')
    spec = importlib.util.spec_from_file_location('firstmate_transport', Path(__file__).with_name('handler.py'))
    transport = importlib.util.module_from_spec(spec); spec.loader.exec_module(transport)

    def ingress(event=None, gateway=None, **kwargs):
        if event is None or gateway is None:
            return None
        source = event.source
        if getattr(getattr(source, 'platform', None), 'value', None) != 'telegram':
            return None
        command = event.get_command()
        if command not in ('fmreply', 'fmstatus'):
            return None
        # This supported hook runs before upstream authorization; explicitly
        # apply that SAME gate before transport. Transport and host also enforce
        # the Telegram user allowlist. No chat-allowlist-only anonymous senders.
        if not gateway._is_user_authorized_for_source(source):
            return None
        adapter = gateway._adapter_for_source(source)
        if adapter is None:
            return None
        context = {'platform':'telegram', 'user_id':source.user_id, 'raw_args':event.get_command_args().strip()}
        busy = len(_pending) >= 4

        async def dispatch():
            if getattr(source, 'chat_type', None) != 'dm':
                message = 'Use the captain’s private Telegram chat for Firstmate replies and status.'
            elif busy:
                message = 'Relay is busy; retry the same question code shortly.'
            else:
                result = await transport.handle('command:' + command, context)
                message = result['message']
            await adapter.send(source.chat_id, message)

        task = asyncio.create_task(dispatch())
        _pending.add(task)
        def completed(done):
            _pending.discard(done)
            # Consume task exceptions; a failed outbound acknowledgement never
            # turns an already-durable answer into a model-backed retry.
            if not done.cancelled():
                done.exception()
        task.add_done_callback(completed)
        return {'action':'skip', 'reason':'authenticated model-free Firstmate relay'}

    ctx.register_hook('pre_gateway_dispatch', ingress)
