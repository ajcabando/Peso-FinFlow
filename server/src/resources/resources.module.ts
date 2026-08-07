import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { DatabaseModule } from '../database/database.module';
import { SyncModule } from '../sync/sync.module';
import {
  AccountsController,
  BillsController,
  BudgetsController,
  SettingsController,
  TagsController,
  TransactionsController,
} from './resources.controller';
import { ResourcesService } from './resources.service';

@Module({
  imports: [DatabaseModule, AuthModule, SyncModule],
  controllers: [
    AccountsController,
    TransactionsController,
    BillsController,
    BudgetsController,
    TagsController,
    SettingsController,
  ],
  providers: [ResourcesService],
})
export class ResourcesModule {}
