import { createHash, randomBytes } from 'node:crypto'

export const BETA_LIMIT_MS = 300_000

const RESERVE_SCRIPT = `
local used = redis.call('GET', KEYS[1])
if not used then return {-2, 0} end
used = tonumber(used)
local requested = tonumber(ARGV[1])
if used + requested > tonumber(ARGV[2]) then return {-1, used} end
local updated = used + requested
redis.call('SET', KEYS[1], updated)
return {1, updated}
`

const REFUND_SCRIPT = `
local used = redis.call('GET', KEYS[1])
if not used then return 0 end
local updated = math.max(0, tonumber(used) - tonumber(ARGV[1]))
redis.call('SET', KEYS[1], updated)
return updated
`

const CONSUME_TOKEN_SCRIPT = `
local owner = redis.call('GET', KEYS[1])
if not owner or owner ~= ARGV[1] then return 0 end
redis.call('DEL', KEYS[1])
return 1
`

function redisConfig() {
  const url = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL
  const token = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN
  if (!url || !token) throw new Error('Redis is not configured.')
  return { url: url.replace(/\/$/, ''), token }
}

export async function redisCommand(command) {
  const { url, token } = redisConfig()
  const response = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command)
  })
  if (!response.ok) throw new Error(`Redis request failed (${response.status}).`)
  const payload = await response.json()
  if (payload.error) throw new Error(`Redis error: ${payload.error}`)
  return payload.result
}

export function normalizeInviteCode(code) {
  return String(code ?? '').trim().toUpperCase().replace(/\s+/g, '')
}

export function inviteHash(code) {
  return createHash('sha256').update(normalizeInviteCode(code)).digest('hex')
}

export function usageKey(code) {
  return `tictic:beta:usage:${inviteHash(code)}`
}

export function durationToMilliseconds(seconds) {
  const value = Number(seconds)
  if (!Number.isFinite(value) || value < 0.25 || value > 26) {
    const error = new Error('Audio duration must be between 0.25 and 26 seconds per segment.')
    error.statusCode = 400
    error.code = 'invalid_duration'
    throw error
  }
  return Math.ceil(value * 1000)
}

export async function getUsage(code) {
  const used = await redisCommand(['GET', usageKey(code)])
  if (used === null) return null
  const usedMs = Number(used)
  return usageSnapshot(usedMs)
}

export async function reserveUsage(code, requestedMs) {
  const result = await redisCommand(['EVAL', RESERVE_SCRIPT, '1', usageKey(code), String(requestedMs), String(BETA_LIMIT_MS)])
  const status = Number(result?.[0])
  const usedMs = Number(result?.[1] ?? 0)
  if (status === -2) return { status: 'invalid_code' }
  if (status === -1) return { status: 'quota_exceeded', ...usageSnapshot(usedMs) }
  return { status: 'ok', ...usageSnapshot(usedMs), reservedMs: requestedMs }
}

export async function refundUsage(code, requestedMs) {
  await redisCommand(['EVAL', REFUND_SCRIPT, '1', usageKey(code), String(requestedMs)])
}

export async function createInvite(label = '') {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const code = generateInviteCode()
    const key = usageKey(code)
    const created = await redisCommand(['SET', key, '0', 'NX'])
    if (created === 'OK') {
      if (label) await redisCommand(['SET', `${key}:label`, label.slice(0, 100)])
      return code
    }
  }
  throw new Error('Could not generate a unique invite code.')
}

export async function issueFormatToken(code) {
  const token = randomBytes(24).toString('base64url')
  await redisCommand(['SET', `tictic:beta:format:${inviteHash(token)}`, inviteHash(code), 'EX', '600'])
  return token
}

export async function consumeFormatToken(code, token) {
  if (!token) return false
  const key = `tictic:beta:format:${inviteHash(token)}`
  const result = await redisCommand(['EVAL', CONSUME_TOKEN_SCRIPT, '1', key, inviteHash(code)])
  return Number(result) === 1
}

export function usageSnapshot(usedMs) {
  const safeUsed = Math.max(0, Math.min(BETA_LIMIT_MS, usedMs))
  return {
    used_seconds: safeUsed / 1000,
    remaining_seconds: (BETA_LIMIT_MS - safeUsed) / 1000,
    limit_seconds: BETA_LIMIT_MS / 1000
  }
}

function generateInviteCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  const bytes = randomBytes(12)
  let value = ''
  for (const byte of bytes) value += alphabet[byte % alphabet.length]
  return `TIC-${value.slice(0, 4)}-${value.slice(4, 8)}-${value.slice(8, 12)}`
}
