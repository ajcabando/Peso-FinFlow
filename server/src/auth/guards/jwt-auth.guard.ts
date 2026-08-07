import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { CurrentUser } from '../current-user.interface';
import { TokenService } from '../token.service';

/**
 * Bearer-token guard. Verifies the JWT via TokenService and attaches the
 * decoded identity to `request.user` as a CurrentUser.
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly tokenService: TokenService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request & { user?: CurrentUser }>();
    const header = request.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing bearer token');
    }
    request.user = this.tokenService.verifyAccessToken(header.slice('Bearer '.length));
    return true;
  }
}
