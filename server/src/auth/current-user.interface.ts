/**
 * Authenticated request identity — populated by `JwtAuthGuard` from the
 * verified access token and attached to `request.user`.
 */
export interface CurrentUser {
  /** users.id */
  userId: string;
  /** devices.id — the client-supplied device id from login */
  deviceId: string;
  /** Refresh-token row id the access token was issued with */
  jti: string;
}
