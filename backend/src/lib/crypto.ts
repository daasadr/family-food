import { hash as argonHash, verify as argonVerify } from '@node-rs/argon2';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

export function hashPassword(plain: string): Promise<string> {
  return argonHash(plain);
}

export async function verifyPassword(storedHash: string, plain: string): Promise<boolean> {
  try {
    return await argonVerify(storedHash, plain);
  } catch {
    return false;
  }
}

/** Náhodný token pro refresh / pozvánku — vrací se uživateli v plaintextu jen jednou. */
export function generateOpaqueToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

/**
 * Deterministický hash pro vyhledání tokenu v DB.
 * Token má plnou entropii, takže SHA-256 stačí — argon2 by znemožnil lookup.
 */
export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export function safeEqual(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  return bufA.length === bufB.length && timingSafeEqual(bufA, bufB);
}

/** Krátký kód pozvánky pro ruční opsání (bez znaků, které jdou zaměnit). */
export function generateInviteCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const raw = randomBytes(10);
  let out = '';
  for (const byte of raw) {
    out += alphabet[byte % alphabet.length];
  }
  return `${out.slice(0, 5)}-${out.slice(5)}`;
}
