import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Transporter } from 'nodemailer';
import { createTransport } from 'nodemailer';

/**
 * Outbound email via generic SMTP (Nodemailer). With no SMTP_HOST configured
 * the service is a no-op that logs — auth keeps working, email-dependent
 * features (verification, password reset) simply report `sent: false`.
 * Email failures are logged, never fatal: a broken mail relay must not take
 * sign-in down.
 */
@Injectable()
export class MailService implements OnModuleDestroy {
  private readonly logger = new Logger(MailService.name);
  private readonly transporter: Transporter | null;
  private readonly from: string;
  private readonly appUrl: string;

  /** Whether a transport exists (SMTP_HOST set). */
  readonly enabled: boolean;

  constructor(config: ConfigService) {
    this.from = config.get<string>('SMTP_FROM', 'FinFlow <no-reply@finflow.local>');
    this.appUrl = config.get<string>('APP_URL', 'http://localhost:8080');

    const host = config.get<string>('SMTP_HOST', '');
    if (!host) {
      this.transporter = null;
      this.enabled = false;
      this.logger.warn(
        'SMTP not configured — verification/password-reset emails are disabled.',
      );
      return;
    }
    const port = config.get<number>('SMTP_PORT', 587);
    const user = config.get<string>('SMTP_USER', '');
    const pass = config.get<string>('SMTP_PASS', '');
    this.transporter = createTransport({
      host,
      port,
      secure: port === 465,
      auth: user ? { user, pass } : undefined,
    });
    this.enabled = true;
  }

  /** Returns true when the email was handed to the transport. */
  async sendVerification(email: string, token: string): Promise<boolean> {
    return this.send({
      to: email,
      subject: 'Verify your FinFlow email',
      text: [
        'Welcome to FinFlow!',
        '',
        `Verify your email to finish setting up your account:`,
        `${this.appUrl}/verify?token=${token}`,
        '',
        `Or paste this token into the app: ${token}`,
        '',
        'This link expires in 60 minutes.',
      ].join('\n'),
    });
  }

  async sendPasswordReset(email: string, token: string): Promise<boolean> {
    return this.send({
      to: email,
      subject: 'FinFlow password reset',
      text: [
        'Someone requested a password reset for your FinFlow account.',
        '',
        `Reset it here: ${this.appUrl}/reset?token=${token}`,
        '',
        `Or paste this token into the app: ${token}`,
        '',
        'This link expires in 30 minutes. If you did not request this, you can safely ignore this email.',
      ].join('\n'),
    });
  }

  private async send(payload: {
    to: string;
    subject: string;
    text: string;
  }): Promise<boolean> {
    if (!this.transporter) {
      this.logger.warn(`Mail disabled — dropping "${payload.subject}" to ${payload.to}`);
      return false;
    }
    try {
      await this.transporter.sendMail({ ...payload, from: this.from });
      return true;
    } catch (error) {
      // Never break auth over a mail failure; the failure is logged and the
      // caller reports `sent: false` honestly.
      this.logger.error(
        `Failed to send "${payload.subject}" to ${payload.to}: ${String(error)}`,
      );
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    if (this.transporter) {
      this.transporter.close();
    }
  }
}
