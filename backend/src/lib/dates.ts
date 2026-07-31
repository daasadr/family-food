import { env } from '../config/env.js';
import { badRequest } from './errors.js';

/** Datum ve tvaru YYYY-MM-DD převede na půlnoc UTC (sloupce typu @db.Date). */
export function parseDateOnly(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    throw badRequest('INVALID_DATE', `Datum musí být ve tvaru YYYY-MM-DD, dostal jsem "${value}".`);
  }
  const [, y, m, d] = match;
  const date = new Date(Date.UTC(Number(y), Number(m) - 1, Number(d)));
  if (
    date.getUTCFullYear() !== Number(y) ||
    date.getUTCMonth() !== Number(m) - 1 ||
    date.getUTCDate() !== Number(d)
  ) {
    throw badRequest('INVALID_DATE', `Datum "${value}" neexistuje.`);
  }
  return date;
}

export function formatDateOnly(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function todayUtc(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

/** Pondělí téhož týdne (ISO týden začíná pondělkem). */
export function startOfIsoWeek(date: Date): Date {
  const day = date.getUTCDay(); // 0 = neděle
  const diff = day === 0 ? -6 : 1 - day;
  return addDays(date, diff);
}

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86_400_000);
}

/**
 * Vynucuje pravidlo ze zadání: plánovat lze max. N měsíců dopředu
 * (konfigurovatelné přes MAX_PLANNING_MONTHS_AHEAD) a ne do minulosti
 * dál než k dnešku.
 */
export function assertWithinPlanningWindow(date: Date): void {
  const today = todayUtc();
  const limit = new Date(today);
  limit.setUTCMonth(limit.getUTCMonth() + env.MAX_PLANNING_MONTHS_AHEAD);

  if (date > limit) {
    throw badRequest(
      'BEYOND_PLANNING_WINDOW',
      `Plánovat lze nejvýše ${env.MAX_PLANNING_MONTHS_AHEAD} měsíce dopředu (do ${formatDateOnly(limit)}).`,
    );
  }
}
