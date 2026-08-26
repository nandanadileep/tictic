import assert from 'node:assert/strict'
import test from 'node:test'
import { BETA_LIMIT_MS, durationToMilliseconds, inviteHash, isInstallationID, normalizeInviteCode, usageSnapshot } from '../lib/store.js'
import { containsNativeIndicScript } from '../lib/sarvam.js'

test('beta allowance is five total minutes', () => {
  assert.equal(BETA_LIMIT_MS, 300_000)
  assert.deepEqual(usageSnapshot(75_500), {
    used_seconds: 75.5,
    remaining_seconds: 224.5,
    limit_seconds: 300
  })
})

test('segment duration is bounded and rounded up', () => {
  assert.equal(durationToMilliseconds(0.251), 251)
  assert.equal(durationToMilliseconds(25), 25_000)
  assert.throws(() => durationToMilliseconds(27), /between/)
})

test('invite codes normalize before hashing', () => {
  assert.equal(normalizeInviteCode(' tic-abcd-2345 '), 'TIC-ABCD-2345')
  assert.equal(inviteHash('tic-abcd'), inviteHash(' TIC-ABCD '))
})

test('only generated installation identifiers auto-provision usage', () => {
  assert.equal(isInstallationID('TIC-INSTALL-550E8400-E29B-41D4-A716-446655440000'), true)
  assert.equal(isInstallationID('TIC-ABCD-2345-EFGH'), false)
  assert.equal(isInstallationID('TIC-INSTALL-NOT-A-UUID'), false)
})

test('native Indic scripts are detected without flagging Roman text', () => {
  assert.equal(containsNativeIndicScript('നമസ്കാരം'), true)
  assert.equal(containsNativeIndicScript('नमस्ते'), true)
  assert.equal(containsNativeIndicScript('namaskaram, sughamano?'), false)
})
