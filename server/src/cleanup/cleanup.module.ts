import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { StorageModule } from '../storage/storage.module';
import { CleanupService } from './cleanup.service';

@Module({
  imports: [DatabaseModule, StorageModule],
  providers: [CleanupService],
  exports: [CleanupService],
})
export class CleanupModule {}
