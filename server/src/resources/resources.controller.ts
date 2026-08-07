import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser as CurrentUserType } from '../auth/current-user.interface';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { ResourceEntity, ResourcesService } from './resources.service';

/** Shared pagination + body handling for every resource controller. */
function pagination(page?: string, limit?: string): { page: number; limit: number } {
  return { page: Number(page ?? 1), limit: Number(limit ?? 50) };
}

@Controller('accounts')
@UseGuards(JwtAuthGuard)
export class AccountsController {
  constructor(private readonly resources: ResourcesService) {}

  @Get()
  list(@CurrentUser() u: CurrentUserType, @Query('page') p?: string, @Query('limit') l?: string) {
    return this.resources.list(u.userId, 'account', pagination(p, l).page, pagination(p, l).limit);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() u: CurrentUserType, @Body() payload: Record<string, unknown>) {
    return this.resources.create(u, 'account', payload);
  }

  @Get(':id')
  get(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.resources.get(u.userId, 'account', id);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: CurrentUserType,
    @Param('id') id: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.resources.update(u, 'account', id, payload);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    await this.resources.remove(u, 'account', id);
  }
}

@Controller('transactions')
@UseGuards(JwtAuthGuard)
export class TransactionsController {
  constructor(private readonly resources: ResourcesService) {}

  @Get()
  list(@CurrentUser() u: CurrentUserType, @Query('page') p?: string, @Query('limit') l?: string) {
    return this.resources.list(u.userId, 'transaction', pagination(p, l).page, pagination(p, l).limit);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() u: CurrentUserType, @Body() payload: Record<string, unknown>) {
    return this.resources.create(u, 'transaction', payload);
  }

  @Get(':id')
  get(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.resources.get(u.userId, 'transaction', id);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: CurrentUserType,
    @Param('id') id: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.resources.update(u, 'transaction', id, payload);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    await this.resources.remove(u, 'transaction', id);
  }
}

@Controller('bills')
@UseGuards(JwtAuthGuard)
export class BillsController {
  constructor(private readonly resources: ResourcesService) {}

  @Get()
  list(@CurrentUser() u: CurrentUserType, @Query('page') p?: string, @Query('limit') l?: string) {
    return this.resources.list(u.userId, 'bill', pagination(p, l).page, pagination(p, l).limit);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() u: CurrentUserType, @Body() payload: Record<string, unknown>) {
    return this.resources.create(u, 'bill', payload);
  }

  @Get(':id')
  get(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.resources.get(u.userId, 'bill', id);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: CurrentUserType,
    @Param('id') id: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.resources.update(u, 'bill', id, payload);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    await this.resources.remove(u, 'bill', id);
  }
}

@Controller('budgets')
@UseGuards(JwtAuthGuard)
export class BudgetsController {
  constructor(private readonly resources: ResourcesService) {}

  @Get()
  list(@CurrentUser() u: CurrentUserType, @Query('page') p?: string, @Query('limit') l?: string) {
    return this.resources.list(u.userId, 'budget', pagination(p, l).page, pagination(p, l).limit);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() u: CurrentUserType, @Body() payload: Record<string, unknown>) {
    return this.resources.create(u, 'budget', payload);
  }

  @Get(':id')
  get(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.resources.get(u.userId, 'budget', id);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: CurrentUserType,
    @Param('id') id: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.resources.update(u, 'budget', id, payload);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    await this.resources.remove(u, 'budget', id);
  }
}

@Controller('tags')
@UseGuards(JwtAuthGuard)
export class TagsController {
  constructor(private readonly resources: ResourcesService) {}

  @Get()
  list(@CurrentUser() u: CurrentUserType, @Query('page') p?: string, @Query('limit') l?: string) {
    return this.resources.list(u.userId, 'tag', pagination(p, l).page, pagination(p, l).limit);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  create(@CurrentUser() u: CurrentUserType, @Body() payload: Record<string, unknown>) {
    return this.resources.create(u, 'tag', payload);
  }

  @Get(':id')
  get(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.resources.get(u.userId, 'tag', id);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: CurrentUserType,
    @Param('id') id: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.resources.update(u, 'tag', id, payload);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    await this.resources.remove(u, 'tag', id);
  }
}

@Controller('settings')
@UseGuards(JwtAuthGuard)
export class SettingsController {
  constructor(private readonly resources: ResourcesService) {}

  @Get()
  list(@CurrentUser() u: CurrentUserType, @Query('page') p?: string, @Query('limit') l?: string) {
    return this.resources.list(u.userId, 'app_setting', pagination(p, l).page, pagination(p, l).limit);
  }

  /** Batch upsert — body is a map of key → value. */
  @Put()
  async updateMany(
    @CurrentUser() u: CurrentUserType,
    @Body() settings: Record<string, unknown>,
  ) {
    const results: Record<string, unknown>[] = [];
    for (const [key, value] of Object.entries(settings)) {
      results.push(
        await this.resources.update(u, 'app_setting', key, { key, value }),
      );
    }
    return { settings: results };
  }

  @Get(':key')
  get(@CurrentUser() u: CurrentUserType, @Param('key') key: string) {
    return this.resources.get(u.userId, 'app_setting', key);
  }

  @Put(':key')
  update(
    @CurrentUser() u: CurrentUserType,
    @Param('key') key: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.resources.update(u, 'app_setting', key, {
      key,
      ...payload,
    });
  }
}
