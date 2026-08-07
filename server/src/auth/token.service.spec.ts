import { JwtService } from '@nestjs/jwt';
import { UnauthorizedException } from '@nestjs/common';
import { TokenService } from './token.service';

describe('TokenService', () => {
  const secret = 'unit-test-secret-0123456789abcdef0123456789abcdef';
  const service = new TokenService(new JwtService({ secret }));

  describe('access tokens', () => {
    it('signs and verifies a round trip', async () => {
      const token = await service.signAccessToken('user-1', 'device-1', 'jti-1');
      expect(service.verifyAccessToken(token)).toEqual({
        userId: 'user-1',
        deviceId: 'device-1',
        jti: 'jti-1',
      });
    });

    it('rejects a token signed with a different secret', async () => {
      const other = new TokenService(new JwtService({ secret: 'another-secret-0123456789abcdef0123456789abcdef' }));
      const token = await other.signAccessToken('user-1', 'device-1', 'jti-1');
      expect(() => service.verifyAccessToken(token)).toThrow(UnauthorizedException);
    });

    it('rejects a tampered token', async () => {
      const token = await service.signAccessToken('user-1', 'device-1', 'jti-1');
      const tampered = token.slice(0, -4) + 'AAAA';
      expect(() => service.verifyAccessToken(tampered)).toThrow(UnauthorizedException);
    });
  });

  describe('refresh tokens', () => {
    it('generates long unique tokens', () => {
      const a = service.generateRefreshToken();
      const b = service.generateRefreshToken();
      expect(a).not.toBe(b);
      expect(a.length).toBeGreaterThanOrEqual(48);
    });

    it('hashes deterministically and never in plaintext', () => {
      const token = service.generateRefreshToken();
      const hash = service.hashRefreshToken(token);
      expect(hash).toHaveLength(64);
      expect(service.hashRefreshToken(token)).toBe(hash);
      expect(hash).not.toContain(token);
    });
  });
});
