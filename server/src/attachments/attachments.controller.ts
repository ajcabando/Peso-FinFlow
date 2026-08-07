import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser as CurrentUserType } from '../auth/current-user.interface';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { ConfirmUploadDto, CreateAttachmentDto } from './attachment.dto';
import { AttachmentsService } from './attachments.service';

@Controller('attachments')
@UseGuards(JwtAuthGuard)
export class AttachmentsController {
  constructor(private readonly attachments: AttachmentsService) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() user: CurrentUserType, @Body() dto: CreateAttachmentDto) {
    return this.attachments.create(user.userId, dto);
  }

  @Patch(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async confirm(
    @CurrentUser() user: CurrentUserType,
    @Param('id', new ParseUUIDPipe()) id: string,
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    @Body() _dto: ConfirmUploadDto,
  ) {
    await this.attachments.confirm(user.userId, id);
  }

  @Get(':id/url')
  url(@CurrentUser() user: CurrentUserType, @Param('id', new ParseUUIDPipe()) id: string) {
    return this.attachments.downloadUrl(user.userId, id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @CurrentUser() user: CurrentUserType,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    await this.attachments.remove(user.userId, id);
  }
}
