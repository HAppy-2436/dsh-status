#!/usr/bin/env node
// dsh-status mock bridge — 按 docs/protocol.md §3.1 实现原生 App 接口，
// 用于 P0 演示与 App 联调（不依赖 DSH 运行）。
//
// 用法：
//   node mock/bridge.mjs [--port 47810] [--dir ~/.dsh-status] [--file bridge.json]
//                        [--cycle] [--quiet]
// 说明：
//   - 写 <dir>/<file>（默认 ~/.dsh-status/bridge.json），App 默认读同一路径；
//     演示时可用 --file bridge.mock.json + App 的 DSH_STATUS_BRIDGE_FILE 隔离。
//   - --cycle 每 8s 推进一次场景，便于观察图标/通知变化。

import http from 'node:http'
import { randomBytes } from 'node:crypto'
import { mkdirSync, writeFileSync, renameSync, rmSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'

const argv = process.argv.slice(2)
const opt = (name, fallback) => {
  const i = argv.indexOf(`--${name}`)
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : fallback
}
const flag = (name) => argv.includes(`--${name}`)

const PORT = Number(opt('port', process.env.DSH_STATUS_MOCK_PORT ?? 47810))
const BRIDGE_DIR = opt('dir', process.env.DSH_STATUS_DIR ?? path.join(homedir(), '.dsh-status'))
const BRIDGE_FILE = path.join(BRIDGE_DIR, opt('file', 'bridge.json'))
const CYCLE = flag('cycle')
const QUIET = flag('quiet')
const TOKEN = randomBytes(32).toString('hex')
const STARTED_AT = Date.now()

const log = (...args) => {
  if (!QUIET) console.log(`[mock ${new Date().toLocaleTimeString('zh-CN')}]`, ...args)
}

// ---------- 假数据 ----------
const F = (min) => Date.now() - min * 60_000
const baseSessions = () => [
  {
    id: 'session-erhu-0001',
    title: '选哪种调音方案？',
    workspaceId: 'w-erhu',
    workspaceTitle: 'erhu',
    status: 'waiting',
    pending: { kind: 'question', summary: '选哪种调音方案？' },
    lastTurn: { kind: 'completed', at: F(3) },
    since: F(1),
    updatedAt: F(1),
  },
  {
    id: 'session-dsh-status-0002',
    title: '实现菜单栏图标',
    workspaceId: 'w-dsh-status',
    workspaceTitle: 'dsh-status',
    status: 'running',
    pending: null,
    lastTurn: null,
    since: F(2),
    updatedAt: F(0.2),
  },
  {
    id: 'session-stability-0003',
    title: '测试出口节点',
    workspaceId: 'w-stability',
    workspaceTitle: 'stability',
    status: 'running',
    pending: null,
    lastTurn: null,
    since: F(5),
    updatedAt: F(0.3),
  },
  {
    id: 'session-dsh-status-0004',
    title: '写桥接协议',
    workspaceId: 'w-dsh-status',
    workspaceTitle: 'dsh-status',
    status: 'completed',
    pending: null,
    lastTurn: { kind: 'completed', at: F(9) },
    since: F(9),
    updatedAt: F(9),
  },
  {
    id: 'session-homebrew-0005',
    title: '梳理 homebrew 配置',
    workspaceId: 'w-homebrew',
    workspaceTitle: 'homebrew',
    status: 'stopped',
    pending: null,
    lastTurn: { kind: 'aborted', at: F(42) },
    since: F(42),
    updatedAt: F(42),
  },
]

const sessions = baseSessions()
const counts = () => {
  const by = { waiting: 0, running: 0, completed: 0, stopped: 0 }
  for (const s of sessions) by[s.status] += 1
  return { ...by, attention: by.waiting + by.completed + by.stopped }
}

const state = () => ({
  version: 1,
  generatedAt: Date.now(),
  dsh: { pid: process.pid, version: 'mock-0.2.1' },
  client: { connected: true, lastPushAt: Date.now() },
  counts: counts(),
  sessions: sessions.map((s) => ({ ...s })),
})

// ---------- SSE ----------
const sseClients = new Set()
function broadcast() {
  const payload = `event: state\ndata: ${JSON.stringify(state())}\n\n`
  for (const res of sseClients) {
    try {
      res.write(payload)
    } catch {
      sseClients.delete(res)
    }
  }
}
setInterval(() => {
  for (const res of sseClients) {
    try {
      res.write(': ping\n\n')
    } catch {
      sseClients.delete(res)
    }
  }
}, 15_000).unref()

// ---------- 场景推进（--cycle） ----------
let phase = 0
const phases = [
  () => log('阶段：等待回答'),
  () => mut((s) => s.id === 'session-erhu-0001' && ((s.status = 'running'), (s.pending = null), (s.since = Date.now()), (s.updatedAt = Date.now()))),
  () => mut((s) => s.id === 'session-dsh-status-0002' && ((s.status = 'completed'), (s.lastTurn = { kind: 'completed', at: Date.now() }), (s.since = Date.now()), (s.updatedAt = Date.now()))),
  () => {
    // 回到初始形态，循环演示
    sessions.splice(0, sessions.length, ...baseSessions())
    broadcast()
  },
]
function mut(fn) {
  for (const s of sessions) fn(s)
  broadcast()
  log('状态变化：', JSON.stringify(counts()))
}
if (CYCLE) {
  setInterval(() => {
    phases[phase % phases.length]()
    phase += 1
    broadcast()
  }, 8000).unref()
}

// ---------- HTTP ----------
const json = (res, code, body) => {
  const data = JSON.stringify(body)
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'content-length': Buffer.byteLength(data),
  })
  res.end(data)
}

const authorized = (req) => {
  const header = req.headers.authorization ?? ''
  return header.startsWith('Bearer ') && header.slice(7) === TOKEN
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? '127.0.0.1'}`)
  const route = `${req.method} ${url.pathname}`
  log(route)

  if (route === 'GET /dsh-status/health') {
    return json(res, 200, { ok: true, version: 1, mock: true })
  }

  if (!url.pathname.startsWith('/dsh-status/')) return json(res, 404, { error: 'not-found' })

  // 原生 App 接口需要 Bearer token
  if (['/dsh-status/state', '/dsh-status/stream', '/dsh-status/command'].includes(url.pathname)) {
    if (!authorized(req)) return json(res, 401, { error: 'unauthorized' })
  }

  if (route === 'GET /dsh-status/state') return json(res, 200, state())

  if (route === 'GET /dsh-status/stream') {
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    })
    res.write(`event: state\ndata: ${JSON.stringify(state())}\n\n`)
    sseClients.add(res)
    req.on('close', () => sseClients.delete(res))
    log(`SSE 客户端连接（当前 ${sseClients.size}）`)
    return
  }

  if (route === 'POST /dsh-status/command') {
    let body = ''
    for await (const chunk of req) body += chunk
    let parsed
    try {
      parsed = JSON.parse(body || '{}')
    } catch {
      return json(res, 400, { error: 'bad-json' })
    }
    if (parsed.type !== 'openSession' || typeof parsed.sessionId !== 'string') {
      return json(res, 400, { error: 'bad-command' })
    }
    const requestId = randomBytes(6).toString('hex')
    log(`收到命令 openSession(${parsed.sessionId}) requestId=${requestId}（mock 不跳转，仅记录）`)
    return json(res, 200, { ok: true, requestId })
  }

  return json(res, 404, { error: 'not-found' })
})

// ---------- bridge.json ----------
mkdirSync(BRIDGE_DIR, { recursive: true, mode: 0o700 })
const bridge = {
  version: 1,
  port: PORT,
  origin: `http://127.0.0.1:${PORT}`,
  token: TOKEN,
  pid: process.pid,
  startedAt: STARTED_AT,
  mock: true,
}
const writeBridge = () => {
  const tmp = `${BRIDGE_FILE}.tmp`
  writeFileSync(tmp, JSON.stringify(bridge, null, 2), { mode: 0o600 })
  renameSync(tmp, BRIDGE_FILE)
}

const cleanup = () => {
  try {
    rmSync(BRIDGE_FILE, { force: true })
  } catch {}
  server.close()
}
process.on('SIGINT', () => (log('退出'), cleanup(), process.exit(0)))
process.on('SIGTERM', () => (log('退出'), cleanup(), process.exit(0)))

server.listen(PORT, '127.0.0.1', () => {
  // --port 0 时由系统分配，写回实际端口
  bridge.port = server.address().port
  bridge.origin = `http://127.0.0.1:${bridge.port}`
  writeBridge()
  log(`mock bridge 已启动：${bridge.origin}`)
  log(`bridge.json：${BRIDGE_FILE}`)
  log(`状态：${JSON.stringify(counts())}`)
})
