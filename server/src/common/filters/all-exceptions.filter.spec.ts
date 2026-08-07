import {
  BadRequestException,
  HttpException,
  HttpStatus,
  InternalServerErrorException,
  NotFoundException,
} from '@nestjs/common';
import type { ArgumentsHost } from '@nestjs/common';
import type { Request, Response } from 'express';
import { AllExceptionsFilter } from './all-exceptions.filter';

describe('AllExceptionsFilter', () => {
  const filter = new AllExceptionsFilter();

  function mockResponse() {
    const json = jest.fn();
    const status = jest.fn(() => ({ json }));
    return { status, json } as unknown as Response;
  }

  function mockHost(response: Response): ArgumentsHost {
    return {
      switchToHttp: () => ({
        getResponse: () => response,
        getRequest: () =>
          ({ url: '/v1/test', headers: {}, method: 'GET' }) as unknown as Request,
      }),
    } as unknown as ArgumentsHost;
  }

  it('maps NotFoundException to a NOT_FOUND envelope with requestId', () => {
    const res = mockResponse();
    filter.catch(new NotFoundException('Not here'), mockHost(res));

    expect(res.status).toHaveBeenCalledWith(404);
    expect(res.json).toHaveBeenCalledWith({
      error: {
        code: 'NOT_FOUND',
        message: 'Not here',
        requestId: 'unknown',
      },
    });
  });

  it('surfaces validation details for array messages', () => {
    const res = mockResponse();
    filter.catch(
      new BadRequestException(['email must be an email', 'password is too short']),
      mockHost(res),
    );

    const payload = (res.json as jest.Mock).mock.calls[0][0];
    expect(payload.error.code).toBe('VALIDATION_FAILED');
    expect(payload.error.details).toEqual([
      'email must be an email',
      'password is too short',
    ]);
    expect(typeof payload.error.message).toBe('string');
  });

  it('surfaces a custom code from an HttpException body (e.g. LEDGER_IMBALANCE)', () => {
    const res = mockResponse();
    filter.catch(
      new HttpException(
        { code: 'LEDGER_IMBALANCE', message: 'Debits must equal credits' },
        HttpStatus.CONFLICT,
      ),
      mockHost(res),
    );

    const payload = (res.json as jest.Mock).mock.calls[0][0];
    expect(res.status).toHaveBeenCalledWith(409);
    expect(payload.error.code).toBe('LEDGER_IMBALANCE');
    expect(payload.error.message).toBe('Debits must equal credits');
  });

  it('masks and logs 5xx HttpException details instead of echoing them', () => {
    const res = mockResponse();
    filter.catch(
      new InternalServerErrorException('user_id=42 password=secret leaked'),
      mockHost(res),
    );

    const payload = (res.json as jest.Mock).mock.calls[0][0];
    expect(res.status).toHaveBeenCalledWith(500);
    expect(payload.error.code).toBe('INTERNAL');
    expect(payload.error.message).toBe('An unexpected error occurred');
    expect(JSON.stringify(payload)).not.toContain('secret');
  });

  it('never leaks internals for unknown exceptions', () => {
    const res = mockResponse();
    filter.catch(
      new Error('SELECT * FROM users; connection string postgres://root:hunter2'),
      mockHost(res),
    );

    const payload = (res.json as jest.Mock).mock.calls[0][0];
    expect(payload.error.code).toBe('INTERNAL');
    expect(payload.error.message).toBe('An unexpected error occurred');
    expect(JSON.stringify(payload)).not.toContain('hunter2');
    expect(JSON.stringify(payload)).not.toContain('SELECT');
  });
});
