import { JWT } from 'google-auth-library';
import { readFileSync } from 'node:fs';

import { env } from '../../config/env.js';

/**
 * Odesílání push notifikací přes FCM HTTP v1.
 *
 * Záměrně bez `firebase-admin` — ten táhne desítky megabajtů závislostí
 * kvůli funkcím, které nepoužíváme. Potřebujeme jediný endpoint a k němu
 * access token ze service accountu.
 */

export interface PushMessage {
  title: string;
  body: string;
  /** Doplňková data pro aplikaci, např. kam po ťuknutí navigovat. */
  data?: Record<string, string>;
}

export interface SendResult {
  sent: number;
  /** Tokeny, které FCM odmítlo jako neplatné — volající je smaže. */
  invalidTokens: string[];
}

export interface PushSender {
  send(tokens: string[], message: PushMessage): Promise<SendResult>;
}

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/** Chyby, po kterých má smysl token zahodit — zařízení už ho nepoužívá. */
const DEAD_TOKEN_CODES = new Set([
  'UNREGISTERED',
  'INVALID_ARGUMENT',
  'SENDER_ID_MISMATCH',
]);

export class FcmSender implements PushSender {
  private readonly client: JWT;

  constructor(
    private readonly projectId: string,
    credentials: { client_email: string; private_key: string },
  ) {
    this.client = new JWT({
      email: credentials.client_email,
      key: credentials.private_key,
      scopes: [FCM_SCOPE],
    });
  }

  async send(tokens: string[], message: PushMessage): Promise<SendResult> {
    if (tokens.length === 0) return { sent: 0, invalidTokens: [] };

    const url = `https://fcm.googleapis.com/v1/projects/${this.projectId}/messages:send`;
    const { token: accessToken } = await this.client.getAccessToken();

    let sent = 0;
    const invalidTokens: string[] = [];

    // FCM v1 nemá dávkové odeslání na víc tokenů jedním requestem, posílá
    // se po jednom. Rodina má jednotky členů, takže je to v pořádku.
    const results = await Promise.allSettled(
      tokens.map(async (deviceToken) => {
        const response = await fetch(url, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${accessToken}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: deviceToken,
              notification: { title: message.title, body: message.body },
              data: message.data,
              android: { priority: 'high' },
              apns: {
                payload: { aps: { sound: 'default' } },
              },
            },
          }),
        });

        if (response.ok) return { deviceToken, ok: true as const };

        const payload = (await response.json().catch(() => null)) as {
          error?: { status?: string; details?: Array<{ errorCode?: string }> };
        } | null;

        const code =
          payload?.error?.details?.find((d) => d.errorCode)?.errorCode
          ?? payload?.error?.status
          ?? String(response.status);

        return { deviceToken, ok: false as const, code };
      }),
    );

    for (const result of results) {
      if (result.status !== 'fulfilled') continue;
      if (result.value.ok) {
        sent += 1;
      } else if (DEAD_TOKEN_CODES.has(result.value.code)) {
        invalidTokens.push(result.value.deviceToken);
      }
    }

    return { sent, invalidTokens };
  }
}

/**
 * Vytvoří odesílač z konfigurace, nebo vrátí null když push není nastavený.
 * Aplikace i API fungují bez něj dál, jen se nic neodešle.
 */
export function createPushSender(
  log: { warn: (msg: string) => void } = console,
): PushSender | null {
  if (!env.FCM_PROJECT_ID) return null;

  // Soubor má přednost — v Dockeru se JSON s uvozovkami přes proměnnou
  // prostředí předává špatně.
  let raw: string | undefined;
  if (env.FCM_SERVICE_ACCOUNT_FILE) {
    try {
      raw = readFileSync(env.FCM_SERVICE_ACCOUNT_FILE, 'utf8');
    } catch (err) {
      // Compose vytvoří na místě chybějícího souboru prázdnou složku.
      // Push se vypne, ale server kvůli tomu nepadá.
      log.warn(
        `Soubor se service accountem nejde přečíst (${env.FCM_SERVICE_ACCOUNT_FILE}): `
          + `${(err as Error).message}. Push notifikace se odesílat nebudou.`,
      );
      return null;
    }
  } else {
    raw = env.FCM_SERVICE_ACCOUNT;
  }

  if (!raw?.trim()) return null;

  try {
    const parsed = JSON.parse(raw) as {
      client_email?: string;
      private_key?: string;
    };
    if (!parsed.client_email || !parsed.private_key) {
      throw new Error('chybí client_email nebo private_key');
    }

    return new FcmSender(env.FCM_PROJECT_ID, {
      client_email: parsed.client_email,
      // V .env bývá klíč na jednom řádku s "\n" jako dvěma znaky.
      private_key: parsed.private_key.replace(/\\n/g, '\n'),
    });
  } catch (err) {
    log.warn(
      `Service account není platný JSON: ${(err as Error).message}. `
        + 'Push notifikace se odesílat nebudou.',
    );
    return null;
  }
}
