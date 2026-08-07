import {
  BadRequestException,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { CurrentUser as CurrentUserType } from '../auth/current-user.interface';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { DevicesService } from './devices.service';

@Controller('devices')
@UseGuards(JwtAuthGuard)
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @Get()
  async list(@CurrentUser() user: CurrentUserType) {
    return {
      devices: await this.devices.listForUser(user.userId, user.deviceId),
    };
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async revoke(
    @CurrentUser() user: CurrentUserType,
    @Param('id', new ParseUUIDPipe()) deviceId: string,
  ) {
    if (deviceId === user.deviceId) {
      throw new BadRequestException('Use logout to sign out the current device');
    }
    await this.devices.revoke(user.userId, deviceId);
  }
}
