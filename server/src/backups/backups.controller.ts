import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser as CurrentUserType } from '../auth/current-user.interface';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CreateBackupDto } from './backup.dto';
import { BackupsService } from './backups.service';

@Controller('backups')
@UseGuards(JwtAuthGuard)
export class BackupsController {
  constructor(private readonly backups: BackupsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() user: CurrentUserType, @Body() dto: CreateBackupDto) {
    return this.backups.create(user.userId, user.deviceId, dto);
  }

  @Get()
  list(
    @CurrentUser() user: CurrentUserType,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.backups.list(user.userId, Number(page ?? 1), Number(limit ?? 50));
  }

  @Patch(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async confirm(
    @CurrentUser() user: CurrentUserType,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    await this.backups.confirm(user.userId, id);
  }

  @Get(':id/url')
  url(@CurrentUser() user: CurrentUserType, @Param('id', new ParseUUIDPipe()) id: string) {
    return this.backups.downloadUrl(user.userId, id);
  }

  @Post(':id/restore')
  @HttpCode(HttpStatus.ACCEPTED)
  restore(@CurrentUser() user: CurrentUserType, @Param('id', new ParseUUIDPipe()) id: string) {
    return this.backups.restore(user.userId, id);
  }
}
