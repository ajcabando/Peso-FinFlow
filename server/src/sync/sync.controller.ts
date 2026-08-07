import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser as CurrentUserType } from '../auth/current-user.interface';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { MAX_PULL_PAGE, PushDto } from './sync-op.dto';
import { SyncService } from './sync.service';

@Controller('sync')
@UseGuards(JwtAuthGuard)
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /**
   * POST /sync/push — append a batch of operations. Always 200: conflicts are
   * reported inside the body (the client re-bases them), never as HTTP errors.
   */
  @Post('push')
  @HttpCode(HttpStatus.OK)
  push(@CurrentUser() user: CurrentUserType, @Body() dto: PushDto) {
    return this.sync.push(user, dto);
  }

  /** GET /sync/pull?cursor=…&limit=… — repeatable, immutable pages. */
  @Get('pull')
  pull(
    @CurrentUser() user: CurrentUserType,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    const parsedCursor = cursor === undefined ? 0 : Number(cursor);
    const parsedLimit = limit === undefined ? MAX_PULL_PAGE : Number(limit);
    if (!Number.isInteger(parsedCursor) || parsedCursor < 0) {
      throw new BadRequestException('cursor must be a non-negative integer');
    }
    if (!Number.isInteger(parsedLimit) || parsedLimit < 1) {
      throw new BadRequestException('limit must be a positive integer');
    }
    return this.sync.pull(user, parsedCursor, parsedLimit);
  }
}
