import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { forbidden, notFound } from '../../lib/errors.js';

const galleryItemSchema = z.object({
  id: z.string(),
  familyId: z.string().nullable(),
  title: z.string(),
  photoUrl: z.string(),
  category: z.string().nullable(),
  isGlobal: z.boolean(),
});

/**
 * Galerie jídel: globální předvytvořená (familyId = null) + vlastní rodinná.
 * GET vrací obě dohromady, zapisovat lze jen do rodinné.
 */
const galleryRoutes: FastifyPluginAsyncZod = async (app) => {
  app.addHook('preHandler', app.requireFamily);

  app.get(
    '/',
    {
      schema: {
        tags: ['gallery'],
        querystring: z.object({
          scope: z.enum(['all', 'global', 'family']).default('all'),
          category: z.string().optional(),
          search: z.string().optional(),
        }),
        response: { 200: z.array(galleryItemSchema) },
      },
    },
    async (req) => {
      const { scope, category, search } = req.query;
      const familyFilter =
        scope === 'global'
          ? { familyId: null }
          : scope === 'family'
            ? { familyId: req.familyId }
            : { OR: [{ familyId: null }, { familyId: req.familyId }] };

      const items = await app.prisma.mealGalleryItem.findMany({
        where: {
          ...familyFilter,
          ...(category ? { category } : {}),
          ...(search ? { title: { contains: search, mode: 'insensitive' as const } } : {}),
        },
        orderBy: [{ familyId: 'desc' }, { createdAt: 'desc' }],
        take: 200,
      });

      return items.map((i) => ({
        id: i.id,
        familyId: i.familyId,
        title: i.title,
        photoUrl: i.photoUrl,
        category: i.category,
        isGlobal: i.familyId === null,
      }));
    },
  );

  app.post(
    '/',
    {
      schema: {
        tags: ['gallery'],
        body: z.object({
          title: z.string().min(1).max(120),
          photoUrl: z.string().url().max(500),
          category: z.string().max(60).optional(),
        }),
        response: { 201: galleryItemSchema },
      },
    },
    async (req, reply) => {
      const item = await app.prisma.mealGalleryItem.create({
        data: {
          familyId: req.familyId,
          title: req.body.title.trim(),
          photoUrl: req.body.photoUrl,
          category: req.body.category?.trim() || null,
        },
      });
      return reply.code(201).send({
        id: item.id,
        familyId: item.familyId,
        title: item.title,
        photoUrl: item.photoUrl,
        category: item.category,
        isGlobal: false,
      });
    },
  );

  app.delete(
    '/:itemId',
    {
      schema: {
        tags: ['gallery'],
        params: z.object({ itemId: z.string().uuid() }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      const item = await app.prisma.mealGalleryItem.findUnique({
        where: { id: req.params.itemId },
      });
      if (!item) throw notFound('GALLERY_ITEM_NOT_FOUND', 'Položka galerie nenalezena.');
      if (item.familyId !== req.familyId) {
        throw forbidden('GLOBAL_GALLERY_READONLY', 'Mazat lze jen položky z vlastní galerie rodiny.');
      }

      await app.prisma.mealGalleryItem.delete({ where: { id: req.params.itemId } });
      return reply.code(204).send(null);
    },
  );
};

export default galleryRoutes;
