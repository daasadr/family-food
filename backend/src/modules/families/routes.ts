import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { AuthService } from '../auth/service.js';
import { FamilyService } from './service.js';

const memberSchema = z.object({
  id: z.string(),
  name: z.string(),
  email: z.string(),
  avatarUrl: z.string().nullable(),
  role: z.enum(['owner', 'member']),
});

const familySchema = z.object({
  id: z.string(),
  name: z.string(),
  subscriptionTier: z.enum(['free', 'premium']),
  shoppingDays: z.array(z.number()),
  createdAt: z.string(),
  members: z.array(memberSchema),
});

const inviteSchema = z.object({
  id: z.string(),
  email: z.string().nullable(),
  status: z.string(),
  expiresAt: z.string(),
  createdAt: z.string(),
});

const familyRoutes: FastifyPluginAsyncZod = async (app) => {
  const service = new FamilyService(app.prisma);
  const authService = new AuthService(app.prisma, app.signAccessToken);

  app.post(
    '/',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['families'],
        body: z.object({ name: z.string().min(1).max(80) }),
        // Uživatel právě získal familyId → potřebuje nové tokeny.
        response: {
          201: z.object({
            family: familySchema,
            tokens: z.object({ accessToken: z.string(), refreshToken: z.string() }),
          }),
        },
      },
    },
    async (req, reply) => {
      const created = await service.createFamily(req.auth.userId, req.body.name);
      const [family, tokens] = await Promise.all([
        service.getFamily(created.id),
        authService.issueTokensForUserId(req.auth.userId),
      ]);
      return reply.code(201).send({ family, tokens });
    },
  );

  app.get(
    '/me',
    {
      preHandler: app.requireFamily,
      schema: { tags: ['families'], response: { 200: familySchema } },
    },
    async (req) => service.getFamily(req.familyId),
  );

  app.patch(
    '/me',
    {
      preHandler: app.requireFamily,
      schema: {
        tags: ['families'],
        body: z.object({
          name: z.string().min(1).max(80).optional(),
          shoppingDays: z.array(z.number().int().min(0).max(6)).max(7).optional(),
        }),
        response: { 200: familySchema },
      },
    },
    async (req) => service.updateFamily(req.familyId, req.auth.role, req.body),
  );

  app.post(
    '/me/leave',
    {
      preHandler: app.requireFamily,
      schema: {
        tags: ['families'],
        response: {
          200: z.object({ tokens: z.object({ accessToken: z.string(), refreshToken: z.string() }) }),
        },
      },
    },
    async (req) => {
      await service.leaveFamily(req.auth.userId, req.familyId, req.auth.role);
      return { tokens: await authService.issueTokensForUserId(req.auth.userId) };
    },
  );

  app.post(
    '/me/transfer-ownership',
    {
      preHandler: app.requireFamily,
      schema: {
        tags: ['families'],
        body: z.object({ userId: z.string().uuid() }),
        response: { 200: familySchema },
      },
    },
    async (req) => service.transferOwnership(req.familyId, req.auth.role, req.body.userId),
  );

  // --- Pozvánky ---------------------------------------------------------

  app.post(
    '/me/invites',
    {
      preHandler: app.requireFamily,
      schema: {
        tags: ['invites'],
        body: z.object({ email: z.string().email().optional() }),
        response: {
          201: z.object({
            id: z.string(),
            code: z.string(),
            email: z.string().nullable(),
            expiresAt: z.string(),
            status: z.string(),
          }),
        },
      },
    },
    async (req, reply) => {
      const invite = await service.createInvite(req.familyId, req.body.email);
      return reply.code(201).send(invite);
    },
  );

  app.get(
    '/me/invites',
    {
      preHandler: app.requireFamily,
      schema: { tags: ['invites'], response: { 200: z.array(inviteSchema) } },
    },
    async (req) => service.listInvites(req.familyId),
  );

  app.delete(
    '/me/invites/:inviteId',
    {
      preHandler: app.requireFamily,
      schema: {
        tags: ['invites'],
        params: z.object({ inviteId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.revokeInvite(req.familyId, req.params.inviteId);
      return reply.code(204).send(null);
    },
  );

  app.post(
    '/invites/accept',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['invites'],
        body: z.object({ code: z.string().min(4) }),
        response: {
          200: z.object({
            family: familySchema,
            tokens: z.object({ accessToken: z.string(), refreshToken: z.string() }),
          }),
        },
      },
    },
    async (req) => {
      const familyId = await service.acceptInvite(req.auth.userId, req.body.code);
      const [family, tokens] = await Promise.all([
        service.getFamily(familyId),
        authService.issueTokensForUserId(req.auth.userId),
      ]);
      return { family, tokens };
    },
  );
};

export default familyRoutes;
