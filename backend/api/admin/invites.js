import { timingSafeEqual } from 'node:crypto'
import { methodNotAllowed, publicError, readJson, sendJson } from '../../lib/http.js'
import { createInvite } from '../../lib/store.js'

export default async function handler(request, response) {
  if (request.method !== 'POST') return methodNotAllowed(response)
  try {
    if (!authorized(request.headers.authorization)) {
      return sendJson(response, 401, { error: 'unauthorized' })
    }
    const body = await readJson(request)
    const count = Math.max(1, Math.min(50, Number.parseInt(body.count ?? '1', 10) || 1))
    const label = typeof body.label === 'string' ? body.label : ''
    const invites = []
    for (let index = 0; index < count; index += 1) {
      invites.push(await createInvite(label ? `${label} ${index + 1}` : ''))
    }
    return sendJson(response, 201, { invites, limit_seconds: 300 })
  } catch (error) {
    const result = publicError(error)
    return sendJson(response, result.status, result.body)
  }
}

function authorized(header) {
  const expected = process.env.ADMIN_SECRET
  const supplied = String(header ?? '').replace(/^Bearer\s+/i, '')
  if (!expected || !supplied) return false
  const left = Buffer.from(expected)
  const right = Buffer.from(supplied)
  return left.length === right.length && timingSafeEqual(left, right)
}
