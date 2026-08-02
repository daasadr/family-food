import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { GeneratedItem, ShoppingListGenerator } from '../src/modules/shopping/ai.js';
import type { ShoppingPromptInput } from '../src/modules/shopping/prompt.js';
import { buildServer } from '../src/server.js';

/**
 * Celý tok nákupního seznamu proti databázi, ale s podstrčeným generátorem
 * místo Claude API — testy tak nepotřebují klíč, síť ani peníze, a přesto
 * ověří sběr jídel, ukládání i práci s položkami.
 */

/** Zaznamená, co dostal, a vrátí pevný seznam. */
class FakeGenerator implements ShoppingListGenerator {
  lastInput: ShoppingPromptInput | null = null;

  constructor(private readonly items: GeneratedItem[]) {}

  async generate(input: ShoppingPromptInput): Promise<GeneratedItem[]> {
    this.lastInput = input;
    return this.items;
  }
}

const fake = new FakeGenerator([
  {
    name: 'treska',
    category: 'ryby',
    quantity: '600 g',
    buyByDate: null,
    note: 'koupit den před vařením',
  },
  { name: 'brambory', category: 'zelenina', quantity: '1 kg', buyByDate: null, note: null },
]);

let app: FastifyInstance;

const auth = (token: string) => ({ authorization: `Bearer ${token}` });
const unique = () => Math.random().toString(36).slice(2, 10);

/** Datum v budoucnu uvnitř povoleného tříměsíčního okna. */
function futureDate(offsetDays = 7): string {
  return new Date(Date.now() + offsetDays * 86_400_000).toISOString().slice(0, 10);
}

async function setupFamilyWithMeal() {
  const registered = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { email: `${unique()}@test.local`, password: 'heslo12345', name: 'Kuchař' },
  });

  const created = await app.inject({
    method: 'POST',
    url: '/api/v1/families',
    headers: auth(registered.json().tokens.accessToken),
    payload: { name: 'Rodina s nákupem' },
  });
  const token = created.json().tokens.accessToken as string;

  const date = futureDate();
  const day = await app.inject({
    method: 'GET',
    url: `/api/v1/planner/days/${date}`,
    headers: auth(token),
  });
  const lunch = day.json().slots.find((s: { slotType: string }) => s.slotType === 'lunch');

  const proposal = await app.inject({
    method: 'POST',
    url: `/api/v1/planner/slots/${lunch.id}/proposals`,
    headers: auth(token),
    payload: { title: 'Pečená treska', description: 'S bramborem' },
  });

  return { token, date, proposalId: proposal.json().id as string };
}

beforeAll(async () => {
  app = await buildServer({ shoppingListGenerator: fake });
  await app.ready();
});

afterAll(async () => {
  await app.close();
});

describe('generování nákupního seznamu', () => {
  it('bez potvrzených jídel odmítne generovat a poradí', async () => {
    const { token, date } = await setupFamilyWithMeal();

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/shopping-lists/generate',
      headers: auth(token),
      payload: { rangeStart: date, rangeEnd: date, includeProposed: false },
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('NO_MEALS_PLANNED');
    expect(res.json().message).toContain('návrhy');
  });

  it('s návrhy vytvoří seznam a předá AI správný kontext', async () => {
    const { token, date } = await setupFamilyWithMeal();

    // Nastavíme dny nákupů, ať se ověří, že se dostanou do promptu.
    await app.inject({
      method: 'PATCH',
      url: '/api/v1/families/me',
      headers: auth(token),
      payload: { shoppingDays: [2, 5] },
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/shopping-lists/generate',
      headers: auth(token),
      payload: { rangeStart: date, rangeEnd: date, includeProposed: true },
    });

    expect(res.statusCode).toBe(201);
    expect(res.json().generatedByAI).toBe(true);
    expect(res.json().items).toHaveLength(2);
    expect(res.json().items.map((i: { name: string }) => i.name)).toContain('treska');

    // Generátor dostal jídlo i nastavení rodiny.
    expect(fake.lastInput?.meals).toHaveLength(1);
    expect(fake.lastInput?.meals[0]?.title).toBe('Pečená treska');
    expect(fake.lastInput?.meals[0]?.slotLabel).toBe('oběd');
    expect(fake.lastInput?.shoppingDays).toEqual([2, 5]);
  });

  it('potvrzené jídlo se do seznamu dostane i bez includeProposed', async () => {
    const { token, date, proposalId } = await setupFamilyWithMeal();

    await app.inject({
      method: 'POST',
      url: `/api/v1/planner/proposals/${proposalId}/confirm`,
      headers: auth(token),
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/shopping-lists/generate',
      headers: auth(token),
      payload: { rangeStart: date, rangeEnd: date, includeProposed: false },
    });

    expect(res.statusCode).toBe(201);
    expect(fake.lastInput?.meals[0]?.status).toBe('confirmed');
  });

  it('odmítne příliš dlouhé rozmezí', async () => {
    const { token } = await setupFamilyWithMeal();

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/shopping-lists/generate',
      headers: auth(token),
      payload: { rangeStart: futureDate(1), rangeEnd: futureDate(60), includeProposed: true },
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('RANGE_TOO_LONG');
  });

  it('odmítne obrácené rozmezí', async () => {
    const { token } = await setupFamilyWithMeal();

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/shopping-lists/generate',
      headers: auth(token),
      payload: { rangeStart: futureDate(10), rangeEnd: futureDate(3), includeProposed: true },
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('INVALID_RANGE');
  });
});

describe('práce s položkami seznamu', () => {
  async function createList() {
    const { token, date } = await setupFamilyWithMeal();
    const list = await app.inject({
      method: 'POST',
      url: '/api/v1/shopping-lists/generate',
      headers: auth(token),
      payload: { rangeStart: date, rangeEnd: date, includeProposed: true },
    });
    return { token, list: list.json() };
  }

  it('odškrtne položku', async () => {
    const { token, list } = await createList();

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/shopping-lists/items/${list.items[0].id}`,
      headers: auth(token),
      payload: { isChecked: true },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().isChecked).toBe(true);
  });

  it('přidá vlastní položku', async () => {
    const { token, list } = await createList();

    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/shopping-lists/${list.id}/items`,
      headers: auth(token),
      payload: { name: 'citron', category: 'ovoce', quantity: '2 ks' },
    });

    expect(res.statusCode).toBe(201);
    expect(res.json().name).toBe('citron');

    const reloaded = await app.inject({
      method: 'GET',
      url: `/api/v1/shopping-lists/${list.id}`,
      headers: auth(token),
    });
    expect(reloaded.json().items).toHaveLength(3);
  });

  it('smaže položku', async () => {
    const { token, list } = await createList();

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/shopping-lists/items/${list.items[0].id}`,
      headers: auth(token),
    });
    expect(res.statusCode).toBe(204);

    const reloaded = await app.inject({
      method: 'GET',
      url: `/api/v1/shopping-lists/${list.id}`,
      headers: auth(token),
    });
    expect(reloaded.json().items).toHaveLength(1);
  });

  it('přehled seznamů ukazuje počty odškrtnutých', async () => {
    const { token, list } = await createList();

    await app.inject({
      method: 'PATCH',
      url: `/api/v1/shopping-lists/items/${list.items[0].id}`,
      headers: auth(token),
      payload: { isChecked: true },
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/shopping-lists',
      headers: auth(token),
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()[0].itemCount).toBe(2);
    expect(res.json()[0].checkedCount).toBe(1);
  });

  it('nepustí k seznamu cizí rodiny', async () => {
    const { list } = await createList();
    const other = await setupFamilyWithMeal();

    const res = await app.inject({
      method: 'GET',
      url: `/api/v1/shopping-lists/${list.id}`,
      headers: auth(other.token),
    });

    expect(res.statusCode).toBe(404);
  });
});
