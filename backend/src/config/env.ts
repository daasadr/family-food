import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default('0.0.0.0'),

  DATABASE_URL: z.string().min(1),

  JWT_ACCESS_SECRET: z.string().min(16),
  JWT_REFRESH_SECRET: z.string().min(16),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),

  MAX_PLANNING_MONTHS_AHEAD: z.coerce.number().int().positive().default(3),
  INVITE_TTL_DAYS: z.coerce.number().int().positive().default(14),

  CORS_ORIGINS: z.string().default('*'),

  ANTHROPIC_API_KEY: z.string().optional(),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  const detail = parsed.error.issues
    .map((i) => `  ${i.path.join('.')}: ${i.message}`)
    .join('\n');
  throw new Error(`Neplatná konfigurace prostředí (.env):\n${detail}`);
}

export const env = parsed.data;

export const corsOrigins: true | string[] =
  env.CORS_ORIGINS.trim() === '*'
    ? true
    : env.CORS_ORIGINS.split(',')
        .map((o) => o.trim())
        .filter(Boolean);
