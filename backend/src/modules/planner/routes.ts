import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { parseDateOnly } from '../../lib/dates.js';
import { PlannerService } from './service.js';

const slotTypeSchema = z.enum(['breakfast', 'lunch', 'dinner', 'snack1', 'snack2', 'custom']);

const authorSchema = z.object({
  id: z.string(),
  name: z.string(),
  avatarUrl: z.string().nullable(),
});

const proposalSchema = z.object({
  id: z.string(),
  mealSlotId: z.string(),
  title: z.string(),
  description: z.string().nullable(),
  photoUrl: z.string().nullable(),
  status: z.enum(['proposed', 'confirmed', 'locked']),
  createdAt: z.string(),
  proposedBy: authorSchema,
  voteCount: z.number(),
  votedByMe: z.boolean(),
  commentCount: z.number(),
});

const slotSchema = z.object({
  id: z.string(),
  slotType: slotTypeSchema,
  customLabel: z.string().nullable(),
  isCustomSlot: z.boolean(),
  sortOrder: z.number(),
  proposals: z.array(proposalSchema),
});

const daySchema = z.object({
  date: z.string(),
  slots: z.array(slotSchema),
});

const templateSchema = z.object({
  id: z.string(),
  slots: z.array(
    z.object({
      id: z.string(),
      slotType: slotTypeSchema,
      enabled: z.boolean(),
      customLabel: z.string().nullable(),
      sortOrder: z.number(),
    }),
  ),
});

const commentSchema = z.object({
  id: z.string(),
  text: z.string(),
  createdAt: z.string(),
  author: authorSchema,
});

const dateParam = z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) });

const plannerRoutes: FastifyPluginAsyncZod = async (app) => {
  const service = new PlannerService(app.prisma);

  // Všechny trasy plánovače vyžadují členství v rodině.
  app.addHook('preHandler', app.requireFamily);

  // --- Šablona ----------------------------------------------------------

  app.get(
    '/template',
    { schema: { tags: ['template'], response: { 200: templateSchema } } },
    async (req) => service.getTemplate(req.familyId),
  );

  app.put(
    '/template',
    {
      schema: {
        tags: ['template'],
        body: z.object({
          slots: z
            .array(
              z.object({
                slotType: slotTypeSchema,
                enabled: z.boolean().default(true),
                customLabel: z.string().max(40).nullish(),
              }),
            )
            .min(1)
            .max(12),
        }),
        response: { 200: templateSchema },
      },
    },
    async (req) => service.replaceTemplateSlots(req.familyId, req.body.slots),
  );

  // --- Kalendář ---------------------------------------------------------

  app.get(
    '/week',
    {
      schema: {
        tags: ['planner'],
        querystring: z.object({ start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) }),
        response: {
          200: z.object({
            weekStart: z.string(),
            weekEnd: z.string(),
            days: z.array(
              z.object({
                date: z.string(),
                slotCount: z.number(),
                proposedCount: z.number(),
                confirmedCount: z.number(),
              }),
            ),
          }),
        },
      },
    },
    async (req) => service.getWeek(req.familyId, parseDateOnly(req.query.start)),
  );

  app.get(
    '/days/:date',
    { schema: { tags: ['planner'], params: dateParam, response: { 200: daySchema } } },
    async (req) => service.getDay(req.familyId, req.auth.userId, parseDateOnly(req.params.date)),
  );

  app.post(
    '/days/:date/slots',
    {
      schema: {
        tags: ['planner'],
        params: dateParam,
        body: z.object({
          slotType: slotTypeSchema.default('custom'),
          customLabel: z.string().min(1).max(40),
        }),
        response: { 201: slotSchema },
      },
    },
    async (req, reply) => {
      const slot = await service.createCustomSlot(
        req.familyId,
        parseDateOnly(req.params.date),
        req.body,
      );
      return reply.code(201).send(slot);
    },
  );

  app.delete(
    '/slots/:slotId',
    {
      schema: {
        tags: ['planner'],
        params: z.object({ slotId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.deleteSlot(req.familyId, req.params.slotId);
      return reply.code(204).send(null);
    },
  );

  // --- Návrhy -----------------------------------------------------------

  app.post(
    '/slots/:slotId/proposals',
    {
      schema: {
        tags: ['proposals'],
        params: z.object({ slotId: z.string().uuid() }),
        body: z.object({
          title: z.string().min(1).max(120),
          description: z.string().max(2000).optional(),
          photoUrl: z.string().url().max(500).optional(),
        }),
        response: { 201: proposalSchema },
      },
    },
    async (req, reply) => {
      const proposal = await service.createProposal(
        req.familyId,
        req.auth.userId,
        req.params.slotId,
        req.body,
      );

      // Ostatní ať vědí, že je o čem hlasovat. Odesílá se na pozadí —
      // nedostupné FCM nesmí shodit uložení návrhu.
      const date = await service.getProposalDate(req.familyId, proposal.id);
      app.notifications.notifyFamilyInBackground({
        familyId: req.familyId,
        excludeUserId: req.auth.userId,
        message: {
          title: 'Nový návrh jídla',
          body: `${proposal.proposedBy.name} navrhuje: ${proposal.title}`,
          data: {
            type: 'proposal',
            proposalId: proposal.id,
            ...(date ? { date } : {}),
          },
        },
      });

      return reply.code(201).send(proposal);
    },
  );

  app.get(
    '/proposals/:proposalId',
    {
      schema: {
        tags: ['proposals'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 200: proposalSchema },
      },
    },
    async (req) => service.getProposal(req.familyId, req.auth.userId, req.params.proposalId),
  );

  app.patch(
    '/proposals/:proposalId',
    {
      schema: {
        tags: ['proposals'],
        params: z.object({ proposalId: z.string().uuid() }),
        body: z.object({
          title: z.string().min(1).max(120).optional(),
          description: z.string().max(2000).nullish(),
          photoUrl: z.string().url().max(500).nullish(),
        }),
        response: { 200: proposalSchema },
      },
    },
    async (req) =>
      service.updateProposal(req.familyId, req.auth.userId, req.params.proposalId, req.body),
  );

  app.delete(
    '/proposals/:proposalId',
    {
      schema: {
        tags: ['proposals'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.deleteProposal(req.familyId, req.auth.userId, req.params.proposalId);
      return reply.code(204).send(null);
    },
  );

  app.post(
    '/proposals/:proposalId/confirm',
    {
      schema: {
        tags: ['proposals'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 200: proposalSchema },
      },
    },
    async (req) => service.confirmProposal(req.familyId, req.auth.userId, req.params.proposalId),
  );

  app.post(
    '/proposals/:proposalId/unlock',
    {
      schema: {
        tags: ['proposals'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 200: proposalSchema },
      },
    },
    async (req) => service.unlockProposal(req.familyId, req.auth.userId, req.params.proposalId),
  );

  // --- Hlasy ------------------------------------------------------------

  app.post(
    '/proposals/:proposalId/vote',
    {
      schema: {
        tags: ['votes'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 200: proposalSchema },
      },
    },
    async (req) => service.vote(req.familyId, req.auth.userId, req.params.proposalId),
  );

  app.delete(
    '/proposals/:proposalId/vote',
    {
      schema: {
        tags: ['votes'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 200: proposalSchema },
      },
    },
    async (req) => service.unvote(req.familyId, req.auth.userId, req.params.proposalId),
  );

  // --- Komentáře --------------------------------------------------------

  app.get(
    '/proposals/:proposalId/comments',
    {
      schema: {
        tags: ['comments'],
        params: z.object({ proposalId: z.string().uuid() }),
        response: { 200: z.array(commentSchema) },
      },
    },
    async (req) => service.listComments(req.familyId, req.params.proposalId),
  );

  app.post(
    '/proposals/:proposalId/comments',
    {
      schema: {
        tags: ['comments'],
        params: z.object({ proposalId: z.string().uuid() }),
        body: z.object({ text: z.string().min(1).max(2000) }),
        response: { 201: commentSchema },
      },
    },
    async (req, reply) => {
      const comment = await service.addComment(
        req.familyId,
        req.auth.userId,
        req.params.proposalId,
        req.body.text,
      );

      const proposal = await service.getProposal(
        req.familyId,
        req.auth.userId,
        req.params.proposalId,
      );

      const date = await service.getProposalDate(req.familyId, req.params.proposalId);
      app.notifications.notifyFamilyInBackground({
        familyId: req.familyId,
        excludeUserId: req.auth.userId,
        message: {
          title: `Komentář k jídlu ${proposal.title}`,
          body: `${comment.author.name}: ${comment.text}`,
          data: {
            type: 'comment',
            proposalId: req.params.proposalId,
            ...(date ? { date } : {}),
          },
        },
      });

      return reply.code(201).send(comment);
    },
  );

  app.delete(
    '/comments/:commentId',
    {
      schema: {
        tags: ['comments'],
        params: z.object({ commentId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.deleteComment(req.familyId, req.auth.userId, req.params.commentId);
      return reply.code(204).send(null);
    },
  );
};

export default plannerRoutes;
