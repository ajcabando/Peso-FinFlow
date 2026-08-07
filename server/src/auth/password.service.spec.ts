import { ConfigService } from '@nestjs/config';
import { PasswordService } from './password.service';

describe('PasswordService', () => {
  const config = new ConfigService({ ARGON2_MEMORY_KIB: '4096', ARGON2_ITERATIONS: '2', ARGON2_PARALLELISM: '1' });
  const service = new PasswordService(config);

  it('hashes and verifies a password', async () => {
    const hash = await service.hash('correct-horse-battery-staple');
    expect(hash).toContain('$argon2id$');
    await expect(service.verify(hash, 'correct-horse-battery-staple')).resolves.toBe(true);
  });

  it('rejects a wrong password', async () => {
    const hash = await service.hash('correct-horse-battery-staple');
    await expect(service.verify(hash, 'wrong-password')).resolves.toBe(false);
  });

  it('never throws on a malformed stored hash (returns false)', async () => {
    await expect(service.verify('not-a-valid-hash', 'whatever')).resolves.toBe(false);
  });
});
