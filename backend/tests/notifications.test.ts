import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import type { PushMessage, PushSender, SendResult } from '../src/modules/notifications/fcm.js';
import { buildServer } from '../src/server.js';

/**
 * Push notifikace proti skutečné databázi, ale s podstrčeným odesílačem —
 * testy nikam nic neposílají a nepotřebují Firebase.
 */

/** Zaznamenává odeslané zprávy; volitelně předstírá neplatné tokeny nebo výpadek. */
class FakeSender implements PushSender {
  calls: Array<{ tokens: string[]; message: PushMessage }> = [];
  invalidTokens: string[] = [];
  failWith: Error | null = null;

  async send(tokens: string[], message: PushMessage): Promise<SendResult> {
    this.calls.push({ tokens, message });
    if (this.failWith) throw this.failWith;
    const invalid = tokens.filter((t) => this.invalidTokens.includes(t));
    return { sent: tokens.length - invalid.length, invalidTokens: invalid };
  }

  reset() {
    this.calls = [];
    this.invalidTokens = [];
    this.failWith = null;
  }

  /** Počká, až doběhne odeslání spuštěné na pozadí. */
  async waitForCall(timeoutMs = 2000): Promise<void> {
    const started = Date.now();
    while (this.calls.length === 0 && Date.now() - started < timeoutMs) {
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
}

const fake = new FakeSender();
let app: FastifyInstance;

const unique = () => Math.random().toString(36).slice(2, 10);
const auth = (token: string) => ({ authorization: `Bearer ${token}` });

function futureDate(offsetDays = 5): string {
  return new Date(Date.now() + offsetDays * 86_400_000).toISOString().slice(0, 10);
}

async function registerWithFamily(name: string) {
  const registered = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email: `${unique()}@test.local`, password: 'heslo12345', name },
  });
  const created = await app.inject({
    method: 'POST',
    url: '/api/v1/families',
    headers: auth(registered.json().tokens.accessToken),
    payload: { name: `Rodina ${unique()}` },
  });
  return created.json().tokens.accessToken as string;
}

/** Přizve druhého člena a vrátí jeho token. */
async function addMember(ownerToken: string, name = 'Druhý') {
  const invite = await app.inject({
    method: 'POST',
    url: '/api/v1/families/me/invites',
    headers: auth(ownerToken),
    payload: {},
  });
  const member = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email: `${unique()}@test.local`, password: 'heslo12345', name },
  });
  const joined = await app.inject({
    method: 'POST',
    url: '/api/v1/families/invites/accept',
    headers: auth(member.json().tokens.accessToken),
    payload: { code: invite.json().code },
  });
  return joined.json().tokens.accessToken as string;
}

async function registerDevice(token: string, deviceToken: string) {
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/notifications/devices',
    headers: auth(token),
    payload: { token: deviceToken, platform: 'android' },
  });
  expect(res.statusCode).toBe(200);
  return res.json();
}

/** Založí návrh jídla a vrátí jeho id. */
async function createProposal(token: string, title: string) {
  const date = futureDate();
  const day = await app.inject({
    method: 'GET',
    url: `/api/v1/planner/days/${date}`,
    headers: auth(token),
  });
  const slot = day.json().slots[0];
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/planner/slots/${slot.id}/proposals`,
    headers: auth(token),
    payload: { title },
  });
  expect(res.statusCode).toBe(201);
  return res.json().id as string;
}

beforeAll(async () => {
  app = await buildServer({ pushSender: fake });
  await app.ready();
});

afterAll(async () => {
  await app.close();
});

beforeEach(() => fake.reset());

describe('registrace zařízení', () => {
  it('zaregistruje token a hlásí, že push je nastavený', async () => {
    const token = await registerWithFamily('Vlastník');

    const body = await registerDevice(token, `dev-${unique()}`);

    expect(body.registered).toBe(true);
    expect(body.pushEnabled).toBe(true);
  });

  it('opakovaná registrace stejného tokenu nezaloží duplicitu', async () => {
    const token = await registerWithFamily('Vlastník');
    const deviceToken = `dev-${unique()}`;

    await registerDevice(token, deviceToken);
    await registerDevice(token, deviceToken);

    const other = await registerWithFamily('Cizí');
    await registerDevice(other, `dev-${unique()}`);

    // Návrh od druhého člena by jinak dorazil na stejné zařízení dvakrát.
    const memberToken = await addMember(token, 'Kolega');
    await registerDevice(memberToken, `dev-${unique()}`);
    fake.reset();

    await createProposal(memberToken, 'Svíčková');
    await fake.waitForCall();

    expect(fake.calls).toHaveLength(1);
    expect(fake.calls[0]!.tokens).toEqual([deviceToken]);
  });

  it('odhlásí zařízení', async () => {
    const token = await registerWithFamily('Vlastník');
    const deviceToken = `dev-${unique()}`;
    await registerDevice(token, deviceToken);

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/v1/notifications/devices',
      headers: auth(token),
      payload: { token: deviceToken },
    });
    expect(res.statusCode).toBe(204);

    // Po odhlášení už zařízení notifikace nedostane.
    const memberToken = await addMember(token, 'Kolega');
    fake.reset();
    await createProposal(memberToken, 'Guláš');
    await fake.waitForCall(500);

    expect(fake.calls).toHaveLength(0);
  });
});

describe('notifikace o návrhu jídla', () => {
  it('dorazí ostatním členům, ne autorovi', async () => {
    const ownerToken = await registerWithFamily('Vlastník');
    const ownerDevice = `dev-owner-${unique()}`;
    await registerDevice(ownerToken, ownerDevice);

    const memberToken = await addMember(ownerToken, 'Petra');
    const memberDevice = `dev-member-${unique()}`;
    await registerDevice(memberToken, memberDevice);

    fake.reset();
    await createProposal(memberToken, 'Rajská omáčka');
    await fake.waitForCall();

    expect(fake.calls).toHaveLength(1);
    // Autor návrhu si vlastní návrh připomínat nepotřebuje.
    expect(fake.calls[0]!.tokens).toEqual([ownerDevice]);
    expect(fake.calls[0]!.message.title).toBe('Nový návrh jídla');
    expect(fake.calls[0]!.message.body).toContain('Petra');
    expect(fake.calls[0]!.message.body).toContain('Rajská omáčka');
    expect(fake.calls[0]!.message.data?.type).toBe('proposal');
  });

  it('nedostane se k členům jiné rodiny', async () => {
    const outsiderToken = await registerWithFamily('Cizí');
    await registerDevice(outsiderToken, `dev-outsider-${unique()}`);

    const ownerToken = await registerWithFamily('Vlastník');
    const memberToken = await addMember(ownerToken, 'Petra');
    const ownerDevice = `dev-owner-${unique()}`;
    await registerDevice(ownerToken, ownerDevice);

    fake.reset();
    await createProposal(memberToken, 'Bramborák');
    await fake.waitForCall();

    expect(fake.calls[0]!.tokens).toEqual([ownerDevice]);
  });

  it('když nikdo nemá zařízení, neodesílá se nic', async () => {
    const ownerToken = await registerWithFamily('Vlastník');
    const memberToken = await addMember(ownerToken, 'Petra');

    fake.reset();
    await createProposal(memberToken, 'Palačinky');
    await fake.waitForCall(500);

    expect(fake.calls).toHaveLength(0);
  });
});

describe('notifikace o komentáři', () => {
  it('nese název jídla i text komentáře', async () => {
    const ownerToken = await registerWithFamily('Vlastník');
    const ownerDevice = `dev-owner-${unique()}`;
    await registerDevice(ownerToken, ownerDevice);

    const proposalId = await createProposal(ownerToken, 'Čočka na kyselo');
    const memberToken = await addMember(ownerToken, 'Petra');

    fake.reset();
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/comments`,
      headers: auth(memberToken),
      payload: { text: 'Radši s vejcem' },
    });
    expect(res.statusCode).toBe(201);
    await fake.waitForCall();

    expect(fake.calls).toHaveLength(1);
    expect(fake.calls[0]!.tokens).toEqual([ownerDevice]);
    expect(fake.calls[0]!.message.title).toContain('Čočka na kyselo');
    expect(fake.calls[0]!.message.body).toContain('Petra');
    expect(fake.calls[0]!.message.body).toContain('Radši s vejcem');
    expect(fake.calls[0]!.message.data?.type).toBe('comment');
  });
});

describe('odolnost vůči výpadku FCM', () => {
  it('návrh jídla se uloží, i když odeslání selže', async () => {
    const ownerToken = await registerWithFamily('Vlastník');
    await registerDevice(ownerToken, `dev-${unique()}`);
    const memberToken = await addMember(ownerToken, 'Petra');

    fake.reset();
    fake.failWith = new Error('FCM je nedostupné');

    // Musí projít normálně — uživatel o svůj návrh nepřijde.
    const proposalId = await createProposal(memberToken, 'Kuskus');
    expect(proposalId).toBeTruthy();
    await fake.waitForCall();
    expect(fake.calls).toHaveLength(1);
  });

  it('tokeny odmítnuté FCM se smažou a podruhé se na ně neposílá', async () => {
    const ownerToken = await registerWithFamily('Vlastník');
    const deadDevice = `dev-dead-${unique()}`;
    await registerDevice(ownerToken, deadDevice);
    const memberToken = await addMember(ownerToken, 'Petra');

    fake.reset();
    fake.invalidTokens = [deadDevice];
    await createProposal(memberToken, 'Rizoto');
    await fake.waitForCall();
    expect(fake.calls[0]!.tokens).toEqual([deadDevice]);

    // Druhý pokus už nemá komu poslat.
    fake.reset();
    await createProposal(memberToken, 'Omeleta');
    await fake.waitForCall(500);
    expect(fake.calls).toHaveLength(0);
  });
});

describe('bez nastaveného FCM', () => {
  it('registrace projde, ale hlásí vypnutý push', async () => {
    const noPush = await buildServer({ pushSender: null });
    await noPush.ready();

    try {
      const registered = await noPush.inject({
        method: 'POST',
        url: '/api/v1/auth/register',
        payload: { email: `${unique()}@test.local`, password: 'heslo12345', name: 'X' },
      });

      const res = await noPush.inject({
        method: 'POST',
        url: '/api/v1/notifications/devices',
        headers: auth(registered.json().tokens.accessToken),
        payload: { token: `dev-${unique()}`, platform: 'ios' },
      });

      expect(res.statusCode).toBe(200);
      expect(res.json().pushEnabled).toBe(false);
    } finally {
      await noPush.close();
    }
  });
});
