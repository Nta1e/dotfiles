import asyncio
import json
import os


async def handle(event_type, context):
    allowed = {x.strip() for x in os.environ.get('TELEGRAM_ALLOWED_USERS', '').split(',') if x.strip().isdigit()}
    if context.get('platform') != 'telegram' or str(context.get('user_id')) not in allowed:
        return {'decision': 'deny', 'message': 'This command is restricted to the captain’s Telegram.'}
    command = event_type.partition(':')[2]
    if command not in ('fmreply', 'fmstatus'):
        return None
    args = context.get('raw_args', '')
    if not isinstance(args, str) or len(args.encode()) > 8192:
        return {'decision':'deny', 'message':'Reply is too large.'}
    envelope = json.dumps({'platform':'telegram', 'user_id':str(context['user_id']), 'command':command, 'args':args}).encode()
    try:
        process = await asyncio.create_subprocess_exec(
            'ssh', '-i', '/opt/data/ssh/id_ed25519', '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=yes', '-o', 'UserKnownHostsFile=/opt/data/ssh/known_hosts',
            '-o', 'ConnectTimeout=8', 'ntaleshadik@host.docker.internal',
            '/usr/bin/python3 /Users/ntaleshadik/dotfiles/home/hermes/fm-telegram-relay.py receive',
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            stdout, _ = await asyncio.wait_for(process.communicate(envelope), timeout=40)
        except (asyncio.TimeoutError, asyncio.CancelledError):
            process.kill()
            await process.wait()
            raise
        if process.returncode:
            message = 'Relay delivery was not confirmed. Retry the same question code; duplicate answers are safely deduplicated.'
        else:
            message = stdout.decode('utf-8', errors='replace').strip()[:3900]
    except asyncio.CancelledError:
        raise
    except Exception:
        message = 'Relay is temporarily unavailable. Retry the same question code; no approval was applied.'
    return {'decision':'handled', 'message':message or 'No status returned.'}
