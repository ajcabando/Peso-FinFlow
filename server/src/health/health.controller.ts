import { Controller, Get, Res } from '@nestjs/common';
import type { Response } from 'express';
import { HealthService } from './health.service';

/**
 * Health endpoints are excluded from the global `/v1` prefix (see main.ts) —
 * nginx and Docker healthchecks need them at the root. Both are public.
 *
 *  GET /health        → 200 { status: "ok", uptimeSeconds }   (liveness)
 *  GET /health/ready  → 200 { status, checks } | 503 { status: "degraded", … }
 */
@Controller()
export class HealthController {
  constructor(private readonly health: HealthService) {}

  @Get('health')
  liveness() {
    return {
      status: 'ok' as const,
      uptimeSeconds: Math.floor(process.uptime()),
    };
  }

  @Get('health/ready')
  async readiness(@Res({ passthrough: true }) response: Response) {
    const result = await this.health.readiness();
    // Degraded is NOT the error envelope — the payload carries the checks map,
    // so set the status directly instead of throwing through the filter.
    if (result.status !== 'ok') {
      response.status(503);
    }
    return result;
  }
}
