import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { badRequest } from '../../lib/errors.js';
import { AuthService } from './service.js';

const publicUserSchema = z.object({
  id: z.string(),
  email: z.string(),
  name: z.string(),
  avatarUrl: z.string().nullable(),
  familyId: z.string().nullable(),
  role: z.enum(['owner', 'member']),
});

const tokenPairSchema = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
});

const sessionSchema = z.object({
  user: publicUserSchema,
  tokens: tokenPairSchema,
});

/** Potvrzení u smazání účtu. Povinné jen pro posledního člena rodiny. */
const deleteBodySchema = z.object({
  confirmFamilyName: z.string().max(80).optional(),
});

const passwordSchema = z
  .string()
  .min(8, 'Heslo musí mít alespoň 8 znaků.')
  .max(128, 'Heslo je příliš dlouhé.');

const authRoutes: FastifyPluginAsyncZod = async (app) => {
  const service = new AuthService(app.prisma, app.signAccessToken);

  app.post(
    '/register',
    {
      schema: {
        tags: ['auth'],
        body: z.object({
          email: z.string().email('Neplatný e-mail.'),
          password: passwordSchema,
          name: z.string().min(1, 'Jméno je povinné.').max(80),
        }),
        response: { 201: sessionSchema },
      },
    },
    async (req, reply) => {
      const result = await service.register(req.body);
      return reply.code(201).send(result);
    },
  );

  app.post(
    '/login',
    {
      schema: {
        tags: ['auth'],
        body: z.object({
          email: z.string().email(),
          password: z.string().min(1),
        }),
        response: { 200: sessionSchema },
      },
    },
    async (req) => service.login(req.body),
  );

  app.post(
    '/refresh',
    {
      schema: {
        tags: ['auth'],
        body: z.object({ refreshToken: z.string().min(1) }),
        response: { 200: sessionSchema },
      },
    },
    async (req) => service.refresh(req.body.refreshToken),
  );

  app.post(
    '/logout',
    {
      schema: {
        tags: ['auth'],
        body: z.object({ refreshToken: z.string().min(1) }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.logout(req.body.refreshToken);
      return reply.code(204).send(null);
    },
  );

  app.get(
    '/me/deletion-preview',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['auth'],
        description:
          'Co smazání účtu způsobí. Klient podle toho staví potvrzovací dialog.',
        response: {
          200: z.object({
            willDeleteFamily: z.boolean(),
            familyName: z.string().nullable(),
            memberCount: z.number(),
            newOwnerName: z.string().nullable(),
            familyData: z
              .object({
                proposals: z.number(),
                comments: z.number(),
                shoppingLists: z.number(),
                galleryItems: z.number(),
                plannedDays: z.number(),
              })
              .nullable(),
          }),
        },
      },
    },
    async (req) => service.deletionPreview(req.auth.userId),
  );

  app.delete(
    '/me',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['auth'],
        description:
          'Nevratné smazání účtu i souvisejících dat (GDPR). Poslední člen '
          + 'rodiny musí potvrdit opsáním názvu rodiny.',
        // Bez `body` ve schématu, aby šlo mazat i požadavkem bez těla —
        // potvrzení je povinné jen pro posledního člena rodiny.
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      const parsed = deleteBodySchema.safeParse(req.body ?? {});
      if (!parsed.success) {
        throw badRequest('VALIDATION_ERROR', 'Neplatná data v požadavku.');
      }
      await service.deleteAccount(req.auth.userId, parsed.data.confirmFamilyName);
      return reply.code(204).send(null);
    },
  );

  app.get(
    '/me',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['auth'],
        response: { 200: publicUserSchema },
      },
    },
    async (req) => service.me(req.auth.userId),
  );
};

export default authRoutes;
