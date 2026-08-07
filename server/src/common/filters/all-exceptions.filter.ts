import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';

/**
 * Maps HTTP status → stable machine-readable code (docs/BACKEND_API.md §1).
 * Anything not listed becomes `REQUEST_FAILED` for handled HTTP errors and
 * `INTERNAL` for unknown exceptions.
 */
const CODE_BY_STATUS: Record<number, string> = {
  [HttpStatus.BAD_REQUEST]: 'VALIDATION_FAILED',
  [HttpStatus.UNAUTHORIZED]: 'UNAUTHORIZED',
  [HttpStatus.FORBIDDEN]: 'FORBIDDEN',
  [HttpStatus.NOT_FOUND]: 'NOT_FOUND',
  [HttpStatus.CONFLICT]: 'CONFLICT',
  [HttpStatus.TOO_MANY_REQUESTS]: 'TOO_MANY_REQUESTS',
  [HttpStatus.UNPROCESSABLE_ENTITY]: 'VALIDATION_FAILED',
  [HttpStatus.INTERNAL_SERVER_ERROR]: 'INTERNAL',
};

/**
 * Global exception filter — the single place HTTP errors become a response.
 * Guarantees: uniform envelope, stable error codes, a request id, and no
 * internals ever leaking (unknown exceptions log locally and return a generic
 * message).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    // pino-http attaches `req.id` (the X-Request-Id it generated).
    const requestId =
      (request as { id?: unknown }).id ??
      request.headers['x-request-id'] ??
      'unknown';

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = 'INTERNAL';
    let message = 'An unexpected error occurred';
    let details: unknown;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      code = CODE_BY_STATUS[status] ?? 'REQUEST_FAILED';
      // Exceptions may carry an explicit machine-readable code (e.g. a
      // `new HttpException({ code: 'LEDGER_IMBALANCE', message }, 409)`) —
      // prefer it over the status-derived default.
      const body = exception.getResponse();
      if (body && typeof body === 'object') {
        const explicit = (body as { code?: unknown }).code;
        if (typeof explicit === 'string' && explicit.length > 0) {
          code = explicit;
        }
      }
      if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
        // 5xx: log the detail for operators, never echo it to the client.
        this.logger.error(
          {
            err: exception,
            requestId,
            path: request.url,
            method: request.method,
          },
          'Request failed with 5xx',
        );
        message = 'An unexpected error occurred';
      } else {
        const body = exception.getResponse();
        if (typeof body === 'string') {
          message = body;
        } else if (body && typeof body === 'object') {
          const b = body as { message?: unknown };
          if (typeof b.message === 'string') {
            message = b.message;
          } else if (Array.isArray(b.message)) {
            // class-validator failure: message is a list of constraint strings.
            message = (b.message as string[]).join('; ');
            details = b.message;
          }
        }
      }
    } else {
      // Never leak stack traces or error text to the client.
      this.logger.error(
        { err: exception, requestId, path: request.url, method: request.method },
        'Unhandled exception',
      );
    }

    response.status(status).json({
      error: {
        code,
        message,
        ...(details !== undefined ? { details } : {}),
        requestId: String(requestId),
      },
    });
  }
}
