#!/usr/bin/env node
// Mattermost <-> Claude Code channel for the `mise` ops bot.
// Inbound: websocket `posted` events from allowlisted directors become
// notifications/claude/channel events; attachments are downloaded to INBOX.
// Outbound: `reply` and `dm` tools, plus permission-relay prompts.
import { execFile } from 'node:child_process'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import { basename, extname, join } from 'node:path'
import { promisify } from 'node:util'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js'
import { z } from 'zod'

const env = name => {
  const v = process.env[name]
  if (!v) throw new Error(`${name} is not set`)
  return v
}
const URL_BASE = env('MATTERMOST_URL').replace(/\/$/, '')
const TOKEN = process.env.MATTERMOST_TOKEN
  ?? (await readFile(env('MATTERMOST_TOKEN_FILE'), 'utf8')).trim()
const ALLOWED = new Set(env('MATTERMOST_ALLOWED_USERS').split(',').map(s => s.trim()).filter(Boolean))
// Channels where money talk is fine; anywhere else staff can read along.
const PRIVATE_CHANNELS = new Set((process.env.MATTERMOST_PRIVATE_CHANNELS ?? '').split(',').filter(Boolean))
const INBOX = env('MISE_INBOX')
const STATE_FILE = join(INBOX, '.threads.json')
const CURSOR_FILE = join(INBOX, '.cursor')
// whisper.cpp wrapper: `$STT <wav>` prints the transcript.
const STT = process.env.MISE_STT_COMMAND
const AUDIO = new Set(['.m4a', '.mp3', '.wav', '.aac', '.caf', '.mp4', '.ogg', '.webm', '.flac'])
const run = promisify(execFile)
// Mattermost rejects posts over 16383 chars; leave headroom for the split marker.
const MAX_POST = 15000

const log = (...a) => console.error('[mattermost]', ...a)

async function api(method, path, body, { raw = false, form } = {}) {
  const headers = { Authorization: `Bearer ${TOKEN}` }
  let payload
  if (form) payload = form
  else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  const res = await fetch(`${URL_BASE}/api/v4${path}`, { method, headers, body: payload })
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${await res.text()}`)
  if (raw) return Buffer.from(await res.arrayBuffer())
  return res.status === 204 ? null : res.json()
}

const me = await api('GET', '/users/me')
const userCache = new Map()
async function user(id) {
  if (!userCache.has(id)) userCache.set(id, await api('GET', `/users/${id}`))
  return userCache.get(id)
}
const channelCache = new Map()
async function channel(id) {
  if (!channelCache.has(id)) channelCache.set(id, await api('GET', `/channels/${id}`))
  return channelCache.get(id)
}

// Threads mise has answered in: follow-ups there need no @mention.
await mkdir(INBOX, { recursive: true })
let threads = new Set()
try { threads = new Set(JSON.parse(await readFile(STATE_FILE, 'utf8'))) } catch {}
async function rememberThread(rootId) {
  if (threads.has(rootId)) return
  threads.add(rootId)
  await writeFile(STATE_FILE, JSON.stringify([...threads].slice(-500)))
}

function split(text) {
  const parts = []
  let rest = text
  while (rest.length > MAX_POST) {
    let cut = rest.lastIndexOf('\n', MAX_POST)
    if (cut < MAX_POST / 2) cut = MAX_POST
    parts.push(rest.slice(0, cut))
    rest = rest.slice(cut).replace(/^\n/, '')
  }
  parts.push(rest)
  return parts
}

async function upload(channelId, paths) {
  const ids = []
  for (const p of paths) {
    const form = new FormData()
    form.append('channel_id', channelId)
    form.append('files', new Blob([await readFile(p)]), basename(p))
    const res = await api('POST', '/files', undefined, { form })
    ids.push(...res.file_infos.map(f => f.id))
  }
  return ids
}

async function post(channelId, rootId, text, files = []) {
  const fileIds = files.length ? await upload(channelId, files) : []
  const parts = split(text)
  let last
  for (const [i, message] of parts.entries()) {
    last = await api('POST', '/posts', {
      channel_id: channelId,
      root_id: rootId ?? '',
      message,
      file_ids: i === parts.length - 1 ? fileIds : [],
    })
  }
  if (rootId) await rememberThread(rootId)
  return last
}

async function dmChannel(userId) {
  return (await api('POST', '/channels/direct', [me.id, userId])).id
}

async function react(postId, emoji, on) {
  try {
    if (on) await api('POST', '/reactions', { user_id: me.id, post_id: postId, emoji_name: emoji })
    else await api('DELETE', `/users/${me.id}/posts/${postId}/reactions/${emoji}`)
  } catch (e) { log('reaction', e.message) }
}

async function transcribe(path) {
  if (!STT) return null
  // whisper wants 16 kHz mono wav; afconvert (macOS) covers m4a/mp3/aac/caf.
  const wav = `${path}.16k.wav`
  let input = path
  try {
    await run('afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', path, wav])
    input = wav
  } catch (e) { log('afconvert', e.message) }
  try {
    const { stdout } = await run(STT, [input], { timeout: 300000 })
    return stdout.trim() || null
  } catch (e) {
    log('stt', e.message)
    return null
  } finally {
    await rm(wav, { force: true })
  }
}

// Posts acknowledged with 👀 and not yet answered, keyed by thread root.
const pending = new Map()
let lastAsker = null

const mcp = new Server(
  { name: 'mattermost', version: '0.1.0' },
  {
    capabilities: {
      experimental: { 'claude/channel': {}, 'claude/channel/permission': {} },
      tools: {},
    },
    instructions: [
      'Messages from the Krunchix directors arrive as <channel source="mattermost" channel_id="..." root_id="..." user="..." private="yes|no" ...>.',
      'Answer every message with the reply tool, passing channel_id and root_id from the tag, so the answer lands in that thread.',
      'Attachments are already downloaded; their local paths are listed under "Attachments:" in the message.',
      'private="no" means staff can read that channel: reply there with one line and send the full answer with the dm tool.',
      'Several messages may arrive together; answer each in its own thread.',
    ].join(' '),
  },
)

mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'reply',
      description: 'Post a message (and optional files) into a Mattermost thread.',
      inputSchema: {
        type: 'object',
        properties: {
          channel_id: { type: 'string' },
          root_id: { type: 'string', description: 'Thread root from the inbound tag' },
          text: { type: 'string', description: 'Mattermost markdown' },
          files: { type: 'array', items: { type: 'string' }, description: 'Absolute paths to attach' },
        },
        required: ['channel_id', 'root_id', 'text'],
      },
    },
    {
      name: 'dm',
      description: 'Send a direct message to a director by name (ntale or sophie).',
      inputSchema: {
        type: 'object',
        properties: {
          to: { type: 'string' },
          text: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
        },
        required: ['to', 'text'],
      },
    },
  ],
}))

mcp.setRequestHandler(CallToolRequestSchema, async req => {
  const args = req.params.arguments ?? {}
  if (req.params.name === 'reply') {
    const p = await post(args.channel_id, args.root_id, args.text, args.files ?? [])
    const ack = pending.get(args.root_id)
    if (ack) { pending.delete(args.root_id); await react(ack, 'eyes', false) }
    return { content: [{ type: 'text', text: `sent (post ${p.id})` }] }
  }
  if (req.params.name === 'dm') {
    const target = DIRECTORS[args.to.toLowerCase()]
    if (!target) throw new Error(`unknown director ${args.to}; use ${Object.keys(DIRECTORS).join(' or ')}`)
    const p = await post(await dmChannel(target), null, args.text, args.files ?? [])
    return { content: [{ type: 'text', text: `sent (post ${p.id})` }] }
  }
  throw new Error(`unknown tool: ${req.params.name}`)
})

// {"ntale": "<user id>", ...}; every id must also be in the allowlist.
const DIRECTORS = JSON.parse(env('MATTERMOST_DIRECTORS'))

mcp.setNotificationHandler(
  z.object({
    method: z.literal('notifications/claude/channel/permission_request'),
    params: z.object({
      request_id: z.string(),
      tool_name: z.string(),
      description: z.string(),
      input_preview: z.string(),
    }),
  }),
  async ({ params }) => {
    if (!lastAsker) return log('permission request with nobody to ask', params.request_id)
    // A mixed channel would show the command to staff; ask in the DM instead.
    const where = lastAsker.private
      ? [lastAsker.channelId, lastAsker.rootId]
      : [await dmChannel(lastAsker.userId), null]
    await post(...where, [
      `:lock: Approval needed: **${params.tool_name}** - ${params.description}`,
      '```',
      params.input_preview.slice(0, 3000),
      '```',
      `Reply \`yes ${params.request_id}\` or \`no ${params.request_id}\``,
    ].join('\n'))
  },
)

const VERDICT_RE = /^\s*(y|yes|n|no)\s+([a-km-z]{5})\s*$/i

// Newest create_at handled, so a reconnect can pick up what arrived while down.
let cursor = Date.now()
try { cursor = Number(await readFile(CURSOR_FILE, 'utf8')) || cursor } catch {}
const seen = new Set()
let handling = Promise.resolve()

// Serialized so backfill and live events reach Claude in posting order.
function handle(p) {
  handling = handling.then(() => onPost(p)).catch(e => log('post', e.stack))
  return handling
}

async function onPost(p) {
  if (seen.has(p.id)) return
  seen.add(p.id)
  if (p.create_at > cursor) {
    cursor = p.create_at
    await writeFile(CURSOR_FILE, String(cursor))
  }
  if (p.user_id === me.id || p.type) return // own posts and system messages
  if (!ALLOWED.has(p.user_id)) return
  const ch = await channel(p.channel_id)
  const rootId = p.root_id || p.id
  const isDm = ch.type === 'D'
  const mentioned = new RegExp(`@${me.username}\\b`, 'i').test(p.message)
  if (!isDm && !mentioned && !threads.has(rootId)) return

  const verdict = VERDICT_RE.exec(p.message.replace(new RegExp(`@${me.username}`, 'ig'), ''))
  if (verdict) {
    await mcp.notification({
      method: 'notifications/claude/channel/permission',
      params: {
        request_id: verdict[2].toLowerCase(),
        behavior: verdict[1].toLowerCase().startsWith('y') ? 'allow' : 'deny',
      },
    })
    return
  }

  const sender = await user(p.user_id)
  const isPrivate = isDm || PRIVATE_CHANNELS.has(p.channel_id)
  const files = []
  const transcripts = []
  for (const id of p.file_ids ?? []) {
    const info = await api('GET', `/files/${id}/info`)
    const path = join(INBOX, `${p.id}_${info.name.replace(/[^\w.-]+/g, '_')}`)
    await writeFile(path, await api('GET', `/files/${id}`, undefined, { raw: true }))
    files.push(path)
    if (info.mime_type?.startsWith('audio/') || AUDIO.has(extname(path).toLowerCase())) {
      const text = await transcribe(path)
      transcripts.push(text ? `Voice note (${basename(path)}): ${text}` : `Voice note ${basename(path)} could not be transcribed.`)
    }
  }

  lastAsker = { userId: p.user_id, channelId: p.channel_id, rootId, private: isPrivate }
  await rememberThread(rootId)
  pending.set(rootId, p.id)
  await react(p.id, 'eyes', true)

  const body = [
    p.message.replace(new RegExp(`@${me.username}\\b`, 'ig'), '').trim(),
    ...transcripts,
    files.length ? `Attachments:\n${files.join('\n')}` : '',
  ].filter(Boolean).join('\n\n')
  await mcp.notification({
    method: 'notifications/claude/channel',
    params: {
      content: body,
      meta: {
        channel_id: p.channel_id,
        root_id: rootId,
        post_id: p.id,
        user: sender.username,
        name: `${sender.first_name} ${sender.last_name}`.trim(),
        channel: isDm ? 'direct message' : ch.display_name,
        private: isPrivate ? 'yes' : 'no',
        sent_at: new Date(p.create_at).toISOString(),
      },
    },
  })
}

// Everything posted in the bot's channels since the cursor, oldest first. Capped
// at a day so a long outage does not replay stale questions.
async function backfill() {
  const since = Math.max(cursor, Date.now() - 86400000)
  const missed = []
  for (const ch of await api('GET', `/users/${me.id}/channels`)) {
    if (ch.last_post_at <= since) continue
    const res = await api('GET', `/channels/${ch.id}/posts?since=${since}`)
    missed.push(...Object.values(res.posts).filter(p => p.create_at > since && !p.delete_at))
  }
  missed.sort((a, b) => a.create_at - b.create_at)
  if (missed.length) log(`backfilling ${missed.length} posts`)
  for (const p of missed) await handle(p)
}

function connect(attempt = 0) {
  const ws = new WebSocket(`${URL_BASE.replace(/^http/, 'ws')}/api/v4/websocket`)
  let alive
  ws.onopen = () => {
    attempt = 0
    ws.send(JSON.stringify({ seq: 1, action: 'authentication_challenge', data: { token: TOKEN } }))
    log('connected as', me.username)
    alive = setInterval(() => ws.send(JSON.stringify({ seq: 2, action: 'ping' })), 30000)
    backfill().catch(e => log('backfill', e.stack))
  }
  ws.onmessage = ev => {
    const msg = JSON.parse(ev.data)
    if (msg.event === 'posted') handle(JSON.parse(msg.data.post))
  }
  ws.onclose = () => {
    clearInterval(alive)
    const wait = Math.min(60000, 1000 * 2 ** attempt)
    log(`disconnected, retrying in ${wait}ms`)
    setTimeout(() => connect(attempt + 1), wait)
  }
  ws.onerror = e => log('ws error', e.message ?? e)
}

await mcp.connect(new StdioServerTransport())
connect()
