import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { DatabaseModule } from '../database/database.module';
import { LedgerController } from './ledger.controller';
import { LedgerService } from './ledger.service';

@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [LedgerController],
  providers: [LedgerService],
})
export class LedgerModule {}
