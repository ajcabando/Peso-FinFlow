import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { Request } from 'express';
import { CurrentUser as CurrentUserIdentity } from '../current-user.interface';

/** Injects the authenticated user/device (set by JwtAuthGuard). */
export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): CurrentUserIdentity => {
    const request = context.switchToHttp().getRequest<
      Request & { user: CurrentUserIdentity }
    >();
    return request.user;
  },
);
