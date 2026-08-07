import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { CurrentUser as CurrentUserType } from '../auth/current-user.interface';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { LedgerService } from './ledger.service';

@Controller('ledger')
@UseGuards(JwtAuthGuard)
export class LedgerController {
  constructor(private readonly ledger: LedgerService) {}

  @Get('accounts/:id/balance')
  accountBalance(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.ledger.accountBalance(u.userId, id);
  }

  @Get('transactions/:id/entries')
  transactionEntries(@CurrentUser() u: CurrentUserType, @Param('id') id: string) {
    return this.ledger.transactionEntries(u.userId, id);
  }
}
