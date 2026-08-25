const MAX_JSON_BYTES = 2_000_000

export async function readJson(request) {
  if (request.body && typeof request.body === 'object' && !Buffer.isBuffer(request.body)) {
    return request.body
  }
  if (typeof request.body === 'string') return JSON.parse(request.body)

  let raw = ''
  for await (const chunk of request) {
    raw += chunk
    if (Buffer.byteLength(raw) > MAX_JSON_BYTES) {
      const error = new Error('Request is too large.')
      error.statusCode = 413
      throw error
    }
  }
  return JSON.parse(raw || '{}')
}

export function sendJson(response, status, body) {
  response.status(status).json(body)
}

export function methodNotAllowed(response, allowed = ['POST']) {
  response.setHeader('Allow', allowed.join(', '))
  sendJson(response, 405, { error: 'method_not_allowed' })
}

export function publicError(error) {
  if (error?.statusCode) {
    return { status: error.statusCode, body: { error: error.code ?? 'request_failed', message: error.message } }
  }
  console.error(error)
  return { status: 500, body: { error: 'internal_error', message: 'TicTic could not complete the request.' } }
}

export function requireString(value, name, maxLength = 10_000) {
  if (typeof value !== 'string' || !value.trim() || value.length > maxLength) {
    const error = new Error(`${name} is invalid.`)
    error.statusCode = 400
    error.code = 'invalid_request'
    throw error
  }
  return value.trim()
}
