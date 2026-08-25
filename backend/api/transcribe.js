import { methodNotAllowed, publicError, readJson, requireString, sendJson } from '../lib/http.js'
import { durationToMilliseconds, issueFormatToken, refundUsage, reserveUsage } from '../lib/store.js'
import { transcribeWithSarvam } from '../lib/sarvam.js'

const ALLOWED_MODES = new Set(['transcribe', 'translate', 'codemix', 'translit', 'verbatim'])
const MAX_AUDIO_BYTES = 1_000_000

export default async function handler(request, response) {
  if (request.method !== 'POST') return methodNotAllowed(response)
  let reservation
  let inviteCode
  try {
    const body = await readJson(request)
    inviteCode = requireString(body.invite_code, 'invite_code', 64)
    const language = requireString(body.language_code, 'language_code', 16)
    const mode = requireString(body.mode, 'mode', 20)
    if (!ALLOWED_MODES.has(mode)) return sendJson(response, 400, { error: 'invalid_mode' })

    const audioBase64 = requireString(body.audio_base64, 'audio_base64', 1_500_000)
    const audio = Buffer.from(audioBase64, 'base64')
    if (!audio.length || audio.length > MAX_AUDIO_BYTES) {
      return sendJson(response, 413, { error: 'invalid_audio', message: 'Audio segment is too large.' })
    }
    const requestedMs = durationToMilliseconds(body.duration_seconds)
    reservation = await reserveUsage(inviteCode, requestedMs)
    if (reservation.status === 'invalid_code') {
      return sendJson(response, 401, { error: 'invalid_invite', message: 'This beta access code is not valid.' })
    }
    if (reservation.status === 'quota_exceeded') {
      return sendJson(response, 402, { error: 'beta_limit_reached', message: 'Your five-minute beta allowance has been used.', ...reservation })
    }

    const transcript = await transcribeWithSarvam({
      audio,
      filename: requireString(body.filename, 'filename', 160),
      mimeType: requireString(body.mime_type, 'mime_type', 80),
      language,
      mode
    })
    const formatToken = await issueFormatToken(inviteCode)
    return sendJson(response, 200, {
      ...transcript,
      format_token: formatToken,
      remaining_seconds: reservation.remaining_seconds,
      limit_seconds: reservation.limit_seconds
    })
  } catch (error) {
    if (reservation?.status === 'ok' && inviteCode) {
      await refundUsage(inviteCode, reservation.reservedMs).catch(console.error)
    }
    const result = publicError(error)
    return sendJson(response, result.status, result.body)
  }
}
