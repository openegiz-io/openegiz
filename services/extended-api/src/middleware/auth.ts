/**
 * Optional authentication middleware for the Extended API.
 *
 * Disabled by default: inside the Dev Profile (and the Production Profile's
 * private network) only Grafana's server-side plugin proxy reaches this API,
 * so per-request authentication would add nothing. When the API is exposed
 * beyond the internal network, set AUTH_ENABLED=true and configure AUTH_TOKEN
 * to gate every request.
 *
 * Environment variables:
 *   AUTH_ENABLED  "true" enables the check; anything else (or unset) disables it.
 *   AUTH_TOKEN    shared secret. Accepted credentials:
 *                   - "Authorization: Bearer <AUTH_TOKEN>"
 *                   - "Authorization: Basic base64(<AUTH_TOKEN>)"
 *                 All requests are rejected if authentication is enabled
 *                 and AUTH_TOKEN is blank or unset.
 *
 * Note: Grafana's plugin proxy injects its own Authorization header (the Ditto
 * basic-auth credentials) into proxied requests; configure AUTH_TOKEN to match
 * those credentials if the API is both proxied and authenticated.
 */
import { NextFunction, Request, RequestHandler, Response } from 'express'

export const AUTH_ENABLED_VAR = 'AUTH_ENABLED'
export const AUTH_TOKEN_VAR = 'AUTH_TOKEN'

export const isAuthEnabled = (): boolean =>
  (process.env[AUTH_ENABLED_VAR] ?? '').trim().toLowerCase() === 'true'

const unauthorized = (res: Response): void => {
  res.status(401).json({ error: 'Unauthorized: a valid Authorization header is required' })
}

const tokenFromHeader = (header: string): string => {
  if (header.startsWith('Basic ')) {
    return Buffer.from(header.slice('Basic '.length), 'base64').toString('utf8')
  }
  return header.replace(/^Bearer\s+/i, '').trim()
}

export const authMiddleware: RequestHandler = (req: Request, res: Response, next: NextFunction) => {
  if (!isAuthEnabled()) {
    next()
    return
  }

  const expected = (process.env[AUTH_TOKEN_VAR] ?? '').trim()
  const header = req.header('authorization')?.trim()
  if (!expected || !header || tokenFromHeader(header) !== expected) {
    unauthorized(res)
    return
  }

  next()
}
