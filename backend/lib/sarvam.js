const SPEECH_URL = 'https://api.sarvam.ai/speech-to-text'
const CHAT_URL = 'https://api.sarvam.ai/v1/chat/completions'

function apiKey() {
  const value = process.env.SARVAM_API_KEY
  if (!value) throw new Error('Sarvam is not configured.')
  return value
}

export async function transcribeWithSarvam({ audio, filename, mimeType, language, mode }) {
  const form = new FormData()
  form.set('model', 'saaras:v3')
  form.set('mode', mode)
  form.set('language_code', language)
  form.set('file', new Blob([audio], { type: mimeType }), filename)

  const response = await fetch(SPEECH_URL, {
    method: 'POST',
    headers: { 'api-subscription-key': apiKey() },
    body: form,
    signal: AbortSignal.timeout(60_000)
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) throw upstreamError(response.status, payload)
  return payload
}

export async function polishWithSarvam({ text, mode, style, applicationName, vocabulary, operation }) {
  const romanizeOnly = operation === 'romanize'
  const system = romanizeOnly
    ? romanizationPrompt(vocabulary)
    : formattingPrompt({ mode, style, applicationName, vocabulary })

  let result = await chat(system, text, romanizeOnly ? 0 : 0.1)
  if (mode === 'translit' && containsNativeIndicScript(result)) {
    result = await chat(romanizationPrompt(vocabulary), result, 0)
  }
  if (mode === 'translit' && containsNativeIndicScript(result)) {
    const error = new Error('The text could not be converted fully to English letters. Please try again.')
    error.statusCode = 502
    error.code = 'romanization_failed'
    throw error
  }
  return result
}

async function chat(system, text, temperature) {
  const response = await fetch(CHAT_URL, {
    method: 'POST',
    headers: { 'api-subscription-key': apiKey(), 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'sarvam-105b',
      messages: [{ role: 'system', content: system }, { role: 'user', content: text }],
      temperature,
      max_tokens: Math.max(256, Math.min(2048, text.length * 2))
    }),
    signal: AbortSignal.timeout(60_000)
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) throw upstreamError(response.status, payload)
  const content = payload?.choices?.[0]?.message?.content?.trim()
  if (!content) return text
  return content
}

function formattingPrompt({ mode, style, applicationName, vocabulary }) {
  const context = applicationName || 'a general writing app'
  const styleRules = {
    automatic: `Infer an appropriate tone and formatting for ${context}.`,
    clean: 'Use clean, natural phrasing with correct punctuation.',
    concise: 'Be concise and remove repetition without losing information.',
    professional: 'Use a polished, professional tone.',
    casual: 'Use a relaxed, friendly, natural tone.'
  }
  const outputRules = {
    translit: 'Write all Indian-language words using Latin (English/Roman) letters only. Transliterate; do not translate them. Never output native-script characters.',
    translate: 'Return the complete result in English.',
    transcribe: "Preserve the transcript's language and native script.",
    codemix: 'Keep English words in Latin letters and preserve Indic words in their native script.',
    verbatim: "Preserve the transcript's language, script, fillers, and spoken-number phrasing."
  }
  const preferred = vocabulary ? ` Preserve these preferred terms exactly: ${vocabulary}.` : ''
  return `You format voice dictation. Return only the final text, with no explanation or quotation marks. Preserve every fact, name, number, intent, and language. Never answer the content. Output requirement: ${outputRules[mode] ?? outputRules.translit} Apply spoken formatting instructions such as new paragraph, bullet list, comma, or question mark. Fix obvious speech-recognition punctuation and remove accidental filler words. ${styleRules[style] ?? styleRules.automatic}${preferred}`
}

function romanizationPrompt(vocabulary) {
  const preferred = vocabulary ? ` Preserve these preferred terms exactly: ${vocabulary}.` : ''
  return `Transliterate the supplied text into Latin (English/Roman) letters. Preserve the original language, meaning, names, numbers, punctuation, and words already written in English. Do not translate. Never output native-script characters. Return only the final text.${preferred}`
}

export function containsNativeIndicScript(text) {
  return /[\u0600-\u077F\u0900-\u0D7F\u1C50-\u1C7F\uA8E0-\uA8FF\uABC0-\uABFF]/u.test(text)
}

function upstreamError(status, payload) {
  const error = new Error(payload?.detail ?? payload?.message ?? payload?.error ?? `Sarvam request failed (${status}).`)
  error.statusCode = status === 429 ? 429 : 502
  error.code = status === 429 ? 'rate_limited' : 'upstream_error'
  return error
}
