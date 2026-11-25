/**
 * Unit tests for the optional authentication middleware.
 *
 * These are pure unit tests: they need no Ditto, MongoDB, or network access,
 * so `yarn lint` (and CI) can always run them. The integration suites in this
 * directory exercise the real API against a live stack instead.
 */
import express from 'express'
import request from 'supertest'
import { authMiddleware, AUTH_ENABLED_VAR, AUTH_TOKEN_VAR } from '../src/middleware/auth'

const withEnv = (vars: Record<string, string | undefined>, fn: () => Promise<void>) => async () => {
  const saved: Record<string, string | undefined> = {}
  for (const key of [AUTH_ENABLED_VAR, AUTH_TOKEN_VAR]) {
    saved[key] = process.env[key]
    if (vars[key] === undefined) delete process.env[key]
    else process.env[key] = vars[key]
  }
  try {
    await fn()
  } finally {
    for (const key of [AUTH_ENABLED_VAR, AUTH_TOKEN_VAR]) {
      if (saved[key] === undefined) delete process.env[key]
      else process.env[key] = saved[key] as string
    }
  }
}

const appWith = () => {
  const app = express()
  app.use(authMiddleware)
  app.get('/api/twins', (_req, res) => { res.status(200).json({ twins: [] }) })
  return app
}

describe('auth middleware disabled (default)', () => {
  it(
    'lets unauthenticated requests through',
    withEnv({ [AUTH_ENABLED_VAR]: undefined }, async () => {
      const res = await request(appWith()).get('/api/twins')
      expect(res.status).toBe(200)
      expect(res.body).toEqual({ twins: [] })
    }),
  )

  it(
    'is off unless AUTH_ENABLED is exactly "true"',
    withEnv({ [AUTH_ENABLED_VAR]: 'false' }, async () => {
      const res = await request(appWith()).get('/api/twins')
      expect(res.status).toBe(200)
    }),
  )

  it(
    'accepts TRUE/True case-insensitively',
    withEnv({ [AUTH_ENABLED_VAR]: 'True' }, async () => {
      const res = await request(appWith()).get('/api/twins')
      expect(res.status).toBe(401) // enabled now: without a token it must reject
    }),
  )
})

describe('auth middleware enabled', () => {
  it(
    'rejects requests without an Authorization header with 401',
    withEnv({ [AUTH_ENABLED_VAR]: 'true' }, async () => {
      const res = await request(appWith()).get('/api/twins')
      expect(res.status).toBe(401)
    }),
  )

  it(
    'rejects a wrong bearer token with 401',
    withEnv({ [AUTH_ENABLED_VAR]: 'true', [AUTH_TOKEN_VAR]: 'secret-token' }, async () => {
      const res = await request(appWith()).get('/api/twins').set('Authorization', 'Bearer wrong')
      expect(res.status).toBe(401)
    }),
  )

  it(
    'accepts a correct bearer token',
    withEnv({ [AUTH_ENABLED_VAR]: 'true', [AUTH_TOKEN_VAR]: 'secret-token' }, async () => {
      const res = await request(appWith()).get('/api/twins').set('Authorization', 'Bearer secret-token')
      expect(res.status).toBe(200)
      expect(res.body).toEqual({ twins: [] })
    }),
  )

  it(
    'accepts correct basic credentials (base64 user:pass)',
    withEnv({ [AUTH_ENABLED_VAR]: 'true', [AUTH_TOKEN_VAR]: 'user:pass' }, async () => {
      const basic = Buffer.from('user:pass', 'utf8').toString('base64')
      const res = await request(appWith()).get('/api/twins').set('Authorization', `Basic ${basic}`)
      expect(res.status).toBe(200)
    }),
  )

  it(
    'with no AUTH_TOKEN configured, any non-empty Authorization header is accepted',
    withEnv({ [AUTH_ENABLED_VAR]: 'true', [AUTH_TOKEN_VAR]: undefined }, async () => {
      const res = await request(appWith()).get('/api/twins').set('Authorization', 'Basic dXNlcjpwYXNz')
      expect(res.status).toBe(200)
    }),
  )
})
