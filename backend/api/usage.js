import { methodNotAllowed, publicError, readJson, requireString, sendJson } from '../lib/http.js'
import { getUsage } from '../lib/store.js'

export default async function handler(request, response) {
  if (request.method !== 'POST') return methodNotAllowed(response)
  try {
    const body = await readJson(request)
    const inviteCode = requireString(body.invite_code, 'invite_code', 64)
    const usage = await getUsage(inviteCode)
    if (!usage) return sendJson(response, 401, { error: 'invalid_invite', message: 'This beta access code is not valid.' })
    return sendJson(response, 200, usage)
  } catch (error) {
    const result = publicError(error)
    return sendJson(response, result.status, result.body)
  }
}
