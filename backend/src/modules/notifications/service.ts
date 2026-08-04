import type { DevicePlatform, PrismaClient } from '@prisma/client';
import type { FastifyBaseLogger } from 'fastify';

import type { PushMessage, PushSender } from './fcm.js';

/**
 * Rozesílání notifikací členům rodiny.
 *
 * Odeslání nikdy neblokuje ani neshazuje požadavek, který ho vyvolal —
 * když je FCM nedostupné, návrh jídla se přesto uloží. Chyba se zaloguje.
 */
export class NotificationService {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly sender: PushSender | null,
    private readonly log: FastifyBaseLogger,
  ) {}

  get isConfigured(): boolean {
    return this.sender !== null;
  }

  /** Zaregistruje token zařízení. Opakované volání jen osvěží lastSeenAt. */
  async registerDevice(userId: string, token: string, platform: DevicePlatform) {
    await this.prisma.deviceToken.upsert({
      where: { token },
      create: { userId, token, platform },
      // Token může přejít na jiný účet, když se na zařízení přihlásí
      // někdo další — proto se přepisuje i userId.
      update: { userId, platform, lastSeenAt: new Date() },
    });
  }

  async unregisterDevice(userId: string, token: string) {
    await this.prisma.deviceToken.deleteMany({ where: { token, userId } });
  }

  /**
   * Pošle notifikaci všem členům rodiny kromě toho, kdo akci vyvolal —
   * vlastní návrh si člověk připomínat nepotřebuje.
   */
  async notifyFamily(input: {
    familyId: string;
    excludeUserId: string;
    message: PushMessage;
  }): Promise<void> {
    if (!this.sender) return;

    const devices = await this.prisma.deviceToken.findMany({
      where: {
        user: { familyId: input.familyId },
        userId: { not: input.excludeUserId },
      },
      select: { token: true },
    });

    if (devices.length === 0) return;

    try {
      const result = await this.sender.send(
        devices.map((d) => d.token),
        input.message,
      );

      // Zařízení, která FCM odmítlo, už notifikace nedostanou — smažeme je,
      // ať se na ně nezkouší posílat donekonečna.
      if (result.invalidTokens.length > 0) {
        await this.prisma.deviceToken.deleteMany({
          where: { token: { in: result.invalidTokens } },
        });
        this.log.info(
          { removed: result.invalidTokens.length },
          'Smazány neplatné tokeny zařízení',
        );
      }
    } catch (err) {
      this.log.error({ err }, 'Odeslání push notifikace selhalo');
    }
  }

  /**
   * Spustí odeslání, ale nečeká na něj. Používá se v handlerech, kde
   * uživatel nemá čekat na FCM.
   */
  notifyFamilyInBackground(input: {
    familyId: string;
    excludeUserId: string;
    message: PushMessage;
  }): void {
    void this.notifyFamily(input).catch((err) => {
      this.log.error({ err }, 'Odeslání push notifikace na pozadí selhalo');
    });
  }
}
