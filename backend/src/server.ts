import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import fastifyStatic from '@fastify/static';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import Fastify, { type FastifyInstance } from 'fastify';
import {
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';
import { ZodError } from 'zod';

import { corsOrigins, env } from './config/env.js';
import { AppError, badRequest } from './lib/errors.js';
import authRoutes from './modules/auth/routes.js';
import familyRoutes from './modules/families/routes.js';
import galleryRoutes from './modules/gallery/routes.js';
import plannerRoutes from './modules/planner/routes.js';
import type { ShoppingListGenerator } from './modules/shopping/ai.js';
import shoppingRoutes from './modules/shopping/routes.js';
import authPlugin from './plugins/auth.js';
import prismaPlugin from './plugins/prisma.js';

export interface BuildServerOptions {
  /**
   * Přebije generátor nákupního seznamu. Testy sem podstrčí deterministickou
   * implementaci, aby nepotřebovaly klíč k AI ani síť.
   */
  shoppingListGenerator?: ShoppingListGenerator;
}

export async function buildServer(
  options: BuildServerOptions = {},
): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: env.NODE_ENV === 'test' ? 'silent' : 'info' },
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  // Fastify odmítá prázdné tělo s hlavičkou `content-type: application/json`.
  // Klienti tak musí u požadavků bez dat posílat aspoň `{}` — což se snadno
  // zapomene. Prázdné tělo tady bereme jako `{}` a řešíme to jednou pro celé API.
  app.addContentTypeParser(
    'application/json',
    { parseAs: 'string' },
    (_req, body, done) => {
      const raw = typeof body === 'string' ? body.trim() : '';
      if (raw === '') return done(null, {});
      try {
        done(null, JSON.parse(raw));
      } catch {
        done(badRequest('INVALID_JSON', 'Tělo požadavku není platný JSON.'), undefined);
      }
    },
  );

  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(cors, { origin: corsOrigins, credentials: true });
  await app.register(rateLimit, {
    max: env.NODE_ENV === 'test' ? 10_000 : 300,
    timeWindow: '1 minute',
  });

  await app.register(prismaPlugin);
  await app.register(authPlugin);

  app.setErrorHandler((error, req, reply) => {
    if (error instanceof AppError) {
      return reply.code(error.statusCode).send({ error: error.code, message: error.message });
    }

    // Chyby validace ze zod schémat.
    const zodError =
      error instanceof ZodError
        ? error
        : (error as { validation?: unknown; cause?: unknown }).cause instanceof ZodError
          ? ((error as { cause: ZodError }).cause)
          : null;

    if (zodError) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Neplatná data v požadavku.',
        details: zodError.issues.map((i) => ({
          path: i.path.join('.'),
          message: i.message,
        })),
      });
    }

    const httpError = error as { statusCode?: number; code?: string; message?: string };
    if (httpError.statusCode && httpError.statusCode < 500) {
      return reply
        .code(httpError.statusCode)
        .send({ error: httpError.code ?? 'REQUEST_ERROR', message: httpError.message });
    }

    req.log.error({ err: error }, 'Neošetřená chyba');
    return reply
      .code(500)
      .send({ error: 'INTERNAL_ERROR', message: 'Na serveru došlo k neočekávané chybě.' });
  });

  app.setNotFoundHandler((req, reply) =>
    reply
      .code(404)
      .send({ error: 'ROUTE_NOT_FOUND', message: `Endpoint ${req.method} ${req.url} neexistuje.` }),
  );

  app.get('/health', async () => ({ status: 'ok', timestamp: new Date().toISOString() }));

  // Veřejné stránky: úvodní a zásady ochrany osobních údajů. Obchody Google
  // Play i App Store vyžadují veřejnou URL se zásadami, tak je servíruje
  // rovnou API — nasazení tím vystačí s jedním portem.
  const publicDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'public');
  await app.register(fastifyStatic, { root: publicDir, prefix: '/' });

  app.get('/privacy', async (_req, reply) => reply.sendFile('privacy.html'));

  await app.register(authRoutes, { prefix: '/api/v1/auth' });
  await app.register(familyRoutes, { prefix: '/api/v1/families' });
  await app.register(plannerRoutes, { prefix: '/api/v1/planner' });
  await app.register(galleryRoutes, { prefix: '/api/v1/gallery' });
  await app.register(shoppingRoutes, {
    prefix: '/api/v1/shopping-lists',
    generator: options.shoppingListGenerator,
  });

  return app;
}
