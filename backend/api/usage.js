import { methodNotAllowed, publicError, readJson, requireString, sendJson } from '../lib/http.js'
import { getUsage } from '../lib/store.js'

export default async function handler(request, response) {
  if (request.method !== 'POST') return methodNotAllowed(response)
  try {
    const body = await readJson(request)
    const installationID = requireString(body.installation_id ?? body.invite_code, 'installation_id', 64)
    const usage = await getUsage(installationID)
    if (!usage) return sendJson(response, 401, { error: 'invalid_installation', message: 'This TicTic installation could not be verified.' })
    return sendJson(response, 200, usage)
  } catch (error) {
    const result = publicError(error)
    return sendJson(response, result.status, result.body)
  }
}
