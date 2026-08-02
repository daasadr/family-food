import Anthropic from '@anthropic-ai/sdk';

import { env } from '../../config/env.js';
import { formatDateOnly, parseDateOnly } from '../../lib/dates.js';
import { AppError } from '../../lib/errors.js';
import {
  buildShoppingListPrompt,
  SHOPPING_LIST_SCHEMA,
  SHOPPING_LIST_SYSTEM_PROMPT,
  type ShoppingPromptInput,
} from './prompt.js';

export interface GeneratedItem {
  name: string;
  category: string;
  quantity: string | null;
  buyByDate: Date | null;
  note: string | null;
}

/**
 * Rozhraní generátoru — v testech se podstrčí deterministická implementace,
 * takže testy nepotřebují API klíč ani síť.
 */
export interface ShoppingListGenerator {
  generate(input: ShoppingPromptInput): Promise<GeneratedItem[]>;
}

const CATEGORIES = new Set([
  'maso',
  'ryby',
  'zelenina',
  'ovoce',
  'mléčné výrobky',
  'pečivo',
  'trvanlivé',
  'mražené',
  'nápoje',
  'ostatní',
]);

/**
 * Ověří a očistí to, co model vrátil. Structured outputs zaručí tvar,
 * ale ne smysluplnost — datum mimo rozmezí nebo neznámou kategorii
 * opravíme tady, ať se do databáze nedostane nesmysl.
 */
export function normalizeGeneratedItems(
  raw: unknown,
  range: { start: string; end: string },
): GeneratedItem[] {
  const parsed = raw as { items?: unknown };
  if (!parsed || !Array.isArray(parsed.items)) {
    throw new AppError(502, 'AI_BAD_RESPONSE', 'AI vrátila odpověď v neočekávaném tvaru.');
  }

  const rangeStart = parseDateOnly(range.start);
  const rangeEnd = parseDateOnly(range.end);

  const items: GeneratedItem[] = [];

  for (const entry of parsed.items) {
    if (typeof entry !== 'object' || entry === null) continue;
    const item = entry as Record<string, unknown>;

    const name = typeof item.name === 'string' ? item.name.trim() : '';
    if (!name) continue;

    const category =
      typeof item.category === 'string' && CATEGORIES.has(item.category)
        ? item.category
        : 'ostatní';

    const quantity =
      typeof item.quantity === 'string' && item.quantity.trim() ? item.quantity.trim() : null;

    const note = typeof item.note === 'string' && item.note.trim() ? item.note.trim() : null;

    // Datum mimo rozmezí přitáhneme k jeho okraji, nesmyslné zahodíme.
    let buyByDate: Date | null = null;
    if (typeof item.buyByDate === 'string') {
      try {
        const parsedDate = parseDateOnly(item.buyByDate);
        if (parsedDate < rangeStart) buyByDate = rangeStart;
        else if (parsedDate > rangeEnd) buyByDate = rangeEnd;
        else buyByDate = parsedDate;
      } catch {
        buyByDate = null;
      }
    }

    items.push({ name, category, quantity, buyByDate, note });
  }

  if (items.length === 0) {
    throw new AppError(
      502,
      'AI_EMPTY_RESPONSE',
      'AI nevrátila žádné položky. Zkus to prosím znovu.',
    );
  }

  // Seřazeno podle data nákupu, ať se seznam čte chronologicky.
  return items.sort((a, b) => {
    if (!a.buyByDate) return 1;
    if (!b.buyByDate) return -1;
    return a.buyByDate.getTime() - b.buyByDate.getTime();
  });
}

export class AnthropicShoppingListGenerator implements ShoppingListGenerator {
  private readonly client: Anthropic;

  constructor(apiKey: string) {
    this.client = new Anthropic({ apiKey });
  }

  async generate(input: ShoppingPromptInput): Promise<GeneratedItem[]> {
    let response;
    try {
      response = await this.client.beta.messages.create({
        model: 'claude-opus-5',
        max_tokens: 16000,
        // Volba surovin a načasování je jednoduchá úvaha — nižší effort
        // stačí a výrazně šetří tokeny i čas.
        output_config: {
          effort: 'low',
          format: { type: 'json_schema', schema: SHOPPING_LIST_SCHEMA },
        },
        // Kdyby bezpečnostní klasifikátor požadavek odmítl, vyřídí ho
        // náhradní model místo toho, aby uživateli spadlo generování.
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        system: SHOPPING_LIST_SYSTEM_PROMPT,
        messages: [{ role: 'user', content: buildShoppingListPrompt(input) }],
      });
    } catch (err) {
      if (err instanceof Anthropic.RateLimitError) {
        throw new AppError(
          503,
          'AI_RATE_LIMITED',
          'AI je právě vytížená. Zkus to prosím za chvíli znovu.',
        );
      }
      if (err instanceof Anthropic.AuthenticationError) {
        throw new AppError(
          500,
          'AI_NOT_CONFIGURED',
          'Klíč k AI službě chybí nebo je neplatný.',
        );
      }
      throw new AppError(502, 'AI_UNAVAILABLE', 'AI služba je nedostupná. Zkus to prosím znovu.');
    }

    if (response.stop_reason === 'refusal') {
      throw new AppError(
        422,
        'AI_REFUSED',
        'AI odmítla tento požadavek zpracovat. Zkus prosím upravit názvy jídel.',
      );
    }

    const textBlock = response.content.find((block) => block.type === 'text');
    if (!textBlock || textBlock.type !== 'text') {
      throw new AppError(502, 'AI_BAD_RESPONSE', 'AI vrátila prázdnou odpověď.');
    }

    let payload: unknown;
    try {
      payload = JSON.parse(textBlock.text);
    } catch {
      throw new AppError(502, 'AI_BAD_RESPONSE', 'AI vrátila odpověď, která není platný JSON.');
    }

    return normalizeGeneratedItems(payload, {
      start: input.rangeStart,
      end: input.rangeEnd,
    });
  }
}

/** Vytvoří generátor, nebo null když není nastavený API klíč. */
export function createShoppingListGenerator(): ShoppingListGenerator | null {
  if (!env.ANTHROPIC_API_KEY) return null;
  return new AnthropicShoppingListGenerator(env.ANTHROPIC_API_KEY);
}

export { formatDateOnly };
