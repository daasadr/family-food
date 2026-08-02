import { describe, expect, it } from 'vitest';

import { AppError } from '../src/lib/errors.js';
import { normalizeGeneratedItems } from '../src/modules/shopping/ai.js';
import { buildShoppingListPrompt } from '../src/modules/shopping/prompt.js';

/**
 * Testy pro AI nákupní seznam. Volání Claude API se netestuje — ověřuje se,
 * co modelu posíláme a jak zacházíme s tím, co vrátí. To jsou přesně ta
 * místa, kde vznikají chyby; samotné API testovat nepotřebujeme.
 */

const RANGE = { start: '2026-08-03', end: '2026-08-09' };

describe('sestavení promptu', () => {
  const input = {
    rangeStart: RANGE.start,
    rangeEnd: RANGE.end,
    shoppingDays: [2, 5],
    today: '2026-08-01',
    meals: [
      {
        date: '2026-08-07',
        slotLabel: 'oběd',
        title: 'Pečená treska',
        description: 'S bramborem',
        status: 'confirmed' as const,
      },
      {
        date: '2026-08-04',
        slotLabel: 'večeře',
        title: 'Zeleninový salát',
        description: null,
        status: 'proposed' as const,
      },
    ],
  };

  it('obsahuje rozmezí, dnešek i jídla', () => {
    const prompt = buildShoppingListPrompt(input);

    expect(prompt).toContain('2026-08-03');
    expect(prompt).toContain('2026-08-09');
    expect(prompt).toContain('Dnes je 2026-08-01');
    expect(prompt).toContain('Pečená treska');
    expect(prompt).toContain('S bramborem');
  });

  it('převádí dny nákupů na české názvy', () => {
    expect(buildShoppingListPrompt(input)).toContain('úterý, pátek');
  });

  it('řekne, když rodina nákupní dny nemá', () => {
    const prompt = buildShoppingListPrompt({ ...input, shoppingDays: [] });
    expect(prompt).toContain('nemá pevné nákupní dny');
  });

  it('označí nepotvrzená jídla', () => {
    const prompt = buildShoppingListPrompt(input);
    // Salát je jen návrh, treska je potvrzená.
    const saladLine = prompt.split('Zeleninový salát')[1] ?? '';
    expect(saladLine).toContain('zatím jen návrh');
    expect(prompt.split('Pečená treska')[1]?.split('\n')[1] ?? '').not.toContain(
      'zatím jen návrh',
    );
  });
});

describe('zpracování odpovědi AI', () => {
  it('přijme platnou odpověď', () => {
    const items = normalizeGeneratedItems(
      {
        items: [
          {
            name: 'treska',
            category: 'ryby',
            quantity: '600 g',
            buyByDate: '2026-08-06',
            note: 'koupit den před vařením',
          },
        ],
      },
      RANGE,
    );

    expect(items).toHaveLength(1);
    expect(items[0]!.name).toBe('treska');
    expect(items[0]!.category).toBe('ryby');
    expect(items[0]!.buyByDate?.toISOString().slice(0, 10)).toBe('2026-08-06');
  });

  it('seřadí položky podle data nákupu', () => {
    const items = normalizeGeneratedItems(
      {
        items: [
          { name: 'treska', category: 'ryby', quantity: '600 g', buyByDate: '2026-08-06' },
          { name: 'mouka', category: 'trvanlivé', quantity: '1 kg', buyByDate: '2026-08-03' },
          { name: 'mrkev', category: 'zelenina', quantity: '500 g', buyByDate: '2026-08-04' },
        ],
      },
      RANGE,
    );

    expect(items.map((i) => i.name)).toEqual(['mouka', 'mrkev', 'treska']);
  });

  it('přitáhne datum mimo rozmezí k jeho okraji', () => {
    const items = normalizeGeneratedItems(
      {
        items: [
          { name: 'brambory', category: 'zelenina', quantity: '2 kg', buyByDate: '2026-07-01' },
          { name: 'chleba', category: 'pečivo', quantity: '1 ks', buyByDate: '2026-12-24' },
        ],
      },
      RANGE,
    );

    const byName = Object.fromEntries(items.map((i) => [i.name, i]));
    expect(byName['brambory']!.buyByDate?.toISOString().slice(0, 10)).toBe(RANGE.start);
    expect(byName['chleba']!.buyByDate?.toISOString().slice(0, 10)).toBe(RANGE.end);
  });

  it('neznámou kategorii přepíše na "ostatní"', () => {
    const items = normalizeGeneratedItems(
      {
        items: [
          { name: 'něco', category: 'vymyšlená kategorie', quantity: '1', buyByDate: RANGE.start },
        ],
      },
      RANGE,
    );

    expect(items[0]!.category).toBe('ostatní');
  });

  it('zahodí položky bez názvu', () => {
    const items = normalizeGeneratedItems(
      {
        items: [
          { name: '   ', category: 'ryby', quantity: '1', buyByDate: RANGE.start },
          { name: 'losos', category: 'ryby', quantity: '1', buyByDate: RANGE.start },
        ],
      },
      RANGE,
    );

    expect(items).toHaveLength(1);
    expect(items[0]!.name).toBe('losos');
  });

  it('zvládne nesmyslné datum', () => {
    const items = normalizeGeneratedItems(
      { items: [{ name: 'sůl', category: 'trvanlivé', quantity: '1', buyByDate: 'někdy' }] },
      RANGE,
    );

    expect(items[0]!.buyByDate).toBeNull();
  });

  it('odmítne odpověď bez pole items', () => {
    expect(() => normalizeGeneratedItems({ neco: 'jineho' }, RANGE)).toThrow(AppError);
    expect(() => normalizeGeneratedItems({ neco: 'jineho' }, RANGE)).toThrow(
      /neočekávaném tvaru/,
    );
  });

  it('odmítne prázdný seznam', () => {
    expect(() => normalizeGeneratedItems({ items: [] }, RANGE)).toThrow(/žádné položky/);
  });

  it('prázdné množství a poznámku uloží jako null', () => {
    const items = normalizeGeneratedItems(
      {
        items: [
          { name: 'vejce', category: 'mléčné výrobky', quantity: '  ', buyByDate: RANGE.start, note: '' },
        ],
      },
      RANGE,
    );

    expect(items[0]!.quantity).toBeNull();
    expect(items[0]!.note).toBeNull();
  });
});
