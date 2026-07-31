import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import {
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';
import { ZodError } from 'zod';

import { corsOrigins, env } from './config/env.js';
import { AppError } from './lib/errors.js';
import authRoutes from './modules/auth/routes.js';
import familyRoutes from './modules/families/routes.js';
import galleryRoutes from './modules/gallery/routes.js';
import plannerRoutes from './modules/planner/routes.js';
import authPlugin from './plugins/auth.js';
import prismaPlugin from './plugins/prisma.js';

export async function buildServer(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: env.NODE_ENV === 'test' ? 'silent' : 'info' },
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

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

  await app.register(authRoutes, { prefix: '/api/v1/auth' });
  await app.register(familyRoutes, { prefix: '/api/v1/families' });
  await app.register(plannerRoutes, { prefix: '/api/v1/planner' });
  await app.register(galleryRoutes, { prefix: '/api/v1/gallery' });

  return app;
}
