import { lwwWinner } from './lww';

const t = (iso: string) => new Date(iso);

describe('lwwWinner (canonical conflict resolution)', () => {
  const base = {
    version: 1,
    updatedAt: t('2026-08-07T10:00:00.000Z'),
    opId: '11111111-1111-4111-8111-111111111111',
  };

  it('prefers the higher version regardless of timestamp', () => {
    expect(
      lwwWinner(base, {
        version: 2,
        updatedAt: t('2020-01-01T00:00:00.000Z'), // older, but newer version
        opId: '22222222-2222-4222-8222-222222222222',
      }),
    ).toBe('incoming');

    expect(
      lwwWinner(
        { ...base, version: 2 },
        { ...base, version: 1, updatedAt: t('2030-01-01T00:00:00.000Z') },
      ),
    ).toBe('current');
  });

  it('breaks version ties by newest updated_at', () => {
    expect(
      lwwWinner(base, {
        version: 1,
        updatedAt: t('2026-08-07T11:00:00.000Z'), // newer
        opId: '22222222-2222-4222-8222-222222222222',
      }),
    ).toBe('incoming');

    expect(
      lwwWinner(base, {
        version: 1,
        updatedAt: t('2026-08-07T09:00:00.000Z'), // older
        opId: '22222222-2222-4222-8222-222222222222',
      }),
    ).toBe('current');
  });

  it('breaks full ties by lexicographically smallest op_id', () => {
    const bigger = {
      version: 1,
      updatedAt: t('2026-08-07T10:00:00.000Z'),
      opId: '99999999-9999-4999-8999-999999999999',
    };
    expect(lwwWinner(base, bigger)).toBe('current'); // 1111… < 9999…
    expect(lwwWinner(bigger, base)).toBe('incoming');
  });

  it('is deterministic and antisymmetric', () => {
    const a = { version: 3, updatedAt: t('2026-08-07T10:00:00.000Z'), opId: 'a' };
    const b = { version: 3, updatedAt: t('2026-08-07T10:00:00.000Z'), opId: 'b' };
    // Smallest opId wins: 'a' < 'b', so a (the current) beats incoming b…
    expect(lwwWinner(a, b)).toBe('current');
    // …and when b is current, incoming a still wins.
    expect(lwwWinner(b, a)).toBe('incoming');
    // Repeatability — same inputs, same result.
    expect(lwwWinner(a, b)).toBe('current');
  });
});
