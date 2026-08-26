import { methodNotAllowed, publicError, readJson, requireString, sendJson } from '../lib/http.js'
import { consumeFormatToken } from '../lib/store.js'
import { polishWithSarvam } from '../lib/sarvam.js'

const ALLOWED_MODES = new Set(['transcribe', 'translate', 'codemix', 'translit', 'verbatim'])
const ALLOWED_STYLES = new Set(['automatic', 'clean', 'concise', 'professional', 'casual'])

export default async function handler(request, response) {
  if (request.method !== 'POST') return methodNotAllowed(response)
  try {
    const body = await readJson(request)
    const installationID = requireString(body.installation_id ?? body.invite_code, 'installation_id', 64)
    const formatToken = requireString(body.format_token, 'format_token', 128)
    const allowed = await consumeFormatToken(installationID, formatToken)
    if (!allowed) return sendJson(response, 401, { error: 'invalid_format_token', message: 'This formatting request has expired.' })

    const mode = requireString(body.mode, 'mode', 20)
    const style = requireString(body.style ?? 'automatic', 'style', 24)
    if (!ALLOWED_MODES.has(mode) || !ALLOWED_STYLES.has(style)) {
      return sendJson(response, 400, { error: 'invalid_request' })
    }
    const text = requireString(body.text, 'text', 30_000)
    const result = await polishWithSarvam({
      text,
      mode,
      style,
      operation: body.operation === 'romanize' ? 'romanize' : 'polish',
      applicationName: typeof body.application_name === 'string' ? body.application_name.slice(0, 120) : '',
      vocabulary: typeof body.vocabulary === 'string' ? body.vocabulary.slice(0, 4_000) : ''
    })
    return sendJson(response, 200, { text: result })
  } catch (error) {
    const result = publicError(error)
    return sendJson(response, result.status, result.body)
  }
}
