import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { parseDateOnly } from '../../lib/dates.js';
import { createShoppingListGenerator, type ShoppingListGenerator } from './ai.js';
import { ShoppingService } from './service.js';

export interface ShoppingRoutesOptions {
  /** Testy sem podstrčí vlastní generátor; v provozu se vytvoří z API klíče. */
  generator?: ShoppingListGenerator;
}

const itemSchema = z.object({
  id: z.string(),
  name: z.string(),
  category: z.string().nullable(),
  quantity: z.string().nullable(),
  buyByDate: z.string().nullable(),
  note: z.string().nullable(),
  isChecked: z.boolean(),
});

const listSchema = z.object({
  id: z.string(),
  rangeStart: z.string(),
  rangeEnd: z.string(),
  generatedAt: z.string(),
  generatedByAI: z.boolean(),
  items: z.array(itemSchema),
});

const listSummarySchema = z.object({
  id: z.string(),
  rangeStart: z.string(),
  rangeEnd: z.string(),
  generatedAt: z.string(),
  generatedByAI: z.boolean(),
  itemCount: z.number(),
  checkedCount: z.number(),
});

const dateString = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const shoppingRoutes: FastifyPluginAsyncZod<ShoppingRoutesOptions> = async (app, opts) => {
  const service = new ShoppingService(
    app.prisma,
    opts.generator ?? createShoppingListGenerator(),
  );

  app.addHook('preHandler', app.requireFamily);

  app.post(
    '/generate',
    {
      // Generování stojí peníze i čas — přísnější limit než zbytek API.
      config: { rateLimit: { max: 10, timeWindow: '1 hour' } },
      schema: {
        tags: ['shopping'],
        body: z.object({
          rangeStart: dateString,
          rangeEnd: dateString,
          includeProposed: z.boolean().default(false),
        }),
        response: { 201: listSchema },
      },
    },
    async (req, reply) => {
      const list = await service.generate(req.familyId, {
        rangeStart: parseDateOnly(req.body.rangeStart),
        rangeEnd: parseDateOnly(req.body.rangeEnd),
        includeProposed: req.body.includeProposed,
      });
      return reply.code(201).send(list);
    },
  );

  app.get(
    '/',
    { schema: { tags: ['shopping'], response: { 200: z.array(listSummarySchema) } } },
    async (req) => service.listLists(req.familyId),
  );

  app.get(
    '/:listId',
    {
      schema: {
        tags: ['shopping'],
        params: z.object({ listId: z.string().uuid() }),
        response: { 200: listSchema },
      },
    },
    async (req) => service.getList(req.familyId, req.params.listId),
  );

  app.delete(
    '/:listId',
    {
      schema: {
        tags: ['shopping'],
        params: z.object({ listId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.deleteList(req.familyId, req.params.listId);
      return reply.code(204).send(null);
    },
  );

  app.post(
    '/:listId/items',
    {
      schema: {
        tags: ['shopping'],
        params: z.object({ listId: z.string().uuid() }),
        body: z.object({
          name: z.string().min(1).max(120),
          category: z.string().max(40).optional(),
          quantity: z.string().max(40).optional(),
          buyByDate: dateString.optional(),
          note: z.string().max(500).optional(),
        }),
        response: { 201: itemSchema },
      },
    },
    async (req, reply) => {
      const { buyByDate, ...rest } = req.body;
      const item = await service.addItem(req.familyId, req.params.listId, {
        ...rest,
        ...(buyByDate ? { buyByDate: parseDateOnly(buyByDate) } : {}),
      });
      return reply.code(201).send(item);
    },
  );

  app.patch(
    '/items/:itemId',
    {
      schema: {
        tags: ['shopping'],
        params: z.object({ itemId: z.string().uuid() }),
        body: z.object({
          name: z.string().min(1).max(120).optional(),
          category: z.string().max(40).nullish(),
          quantity: z.string().max(40).nullish(),
          buyByDate: dateString.nullish(),
          note: z.string().max(500).nullish(),
          isChecked: z.boolean().optional(),
        }),
        response: { 200: itemSchema },
      },
    },
    async (req) => {
      const { buyByDate, ...rest } = req.body;
      return service.updateItem(req.familyId, req.params.itemId, {
        ...rest,
        ...(buyByDate !== undefined
          ? { buyByDate: buyByDate ? parseDateOnly(buyByDate) : null }
          : {}),
      });
    },
  );

  app.delete(
    '/items/:itemId',
    {
      schema: {
        tags: ['shopping'],
        params: z.object({ itemId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await service.deleteItem(req.familyId, req.params.itemId);
      return reply.code(204).send(null);
    },
  );
};

export default shoppingRoutes;
