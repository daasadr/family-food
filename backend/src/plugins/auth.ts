import fastifyJwt from '@fastify/jwt';
import type { FamilyRole } from '@prisma/client';
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';

import { env } from '../config/env.js';
import { forbidden, unauthorized } from '../lib/errors.js';

/** Payload access tokenu. */
export interface AccessTokenPayload {
  sub: string;
  familyId: string | null;
  role: FamilyRole;
}

/** Ověřený uživatel připojený k requestu po `authenticate`. */
export interface AuthContext {
  userId: string;
  familyId: string | null;
  role: FamilyRole;
}

declare module 'fastify' {
  interface FastifyInstance {
    /** preHandler: vyžaduje platný access token. */
    authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    /** preHandler: vyžaduje platný token *a* členství v rodině. */
    requireFamily: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    signAccessToken: (payload: AccessTokenPayload) => string;
  }

  interface FastifyRequest {
    auth: AuthContext;
    /** Naplněno až po `requireFamily` — zaručeně non-null familyId. */
    familyId: string;
  }
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: AccessTokenPayload;
    user: AccessTokenPayload;
  }
}

const authPlugin: FastifyPluginAsync = async (app) => {
  await app.register(fastifyJwt, {
    secret: env.JWT_ACCESS_SECRET,
    sign: { expiresIn: env.ACCESS_TOKEN_TTL },
  });

  // Hodnoty se naplní v preHandleru; deklarace jen rezervuje tvar requestu.
  app.decorateRequest('auth');
  app.decorateRequest('familyId');

  app.decorate('signAccessToken', function (payload: AccessTokenPayload) {
    return app.jwt.sign(payload);
  });

  app.decorate('authenticate', async function (req: FastifyRequest) {
    try {
      await req.jwtVerify();
    } catch {
      throw unauthorized('INVALID_TOKEN', 'Přihlašovací token chybí nebo je neplatný.');
    }
    req.auth = {
      userId: req.user.sub,
      familyId: req.user.familyId ?? null,
      role: req.user.role,
    };
  });

  app.decorate('requireFamily', async function (req: FastifyRequest, reply: FastifyReply) {
    await app.authenticate(req, reply);
    if (!req.auth.familyId) {
      throw forbidden(
        'NO_FAMILY',
        'Nejsi členem žádné rodiny. Nejdřív si založ rodinu nebo přijmi pozvánku.',
      );
    }
    req.familyId = req.auth.familyId;
  });
};

export default fp(authPlugin, { name: 'auth' });
