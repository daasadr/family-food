import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

const notificationRoutes: FastifyPluginAsyncZod = async (app) => {
  app.post(
    '/devices',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['notifications'],
        description:
          'Zaregistruje zařízení pro push notifikace. Aplikace volá po každém '
          + 'startu — FCM token se může kdykoli změnit.',
        body: z.object({
          token: z.string().min(1).max(4096),
          platform: z.enum(['android', 'ios', 'web']),
        }),
        response: {
          200: z.object({
            registered: z.boolean(),
            /** False, když na serveru není nastavené FCM — klient to pozná. */
            pushEnabled: z.boolean(),
          }),
        },
      },
    },
    async (req) => {
      await app.notifications.registerDevice(
        req.auth.userId,
        req.body.token,
        req.body.platform,
      );
      return { registered: true, pushEnabled: app.notifications.isConfigured };
    },
  );

  app.delete(
    '/devices',
    {
      preHandler: app.authenticate,
      schema: {
        tags: ['notifications'],
        description: 'Odhlásí zařízení z notifikací — volá se při odhlášení.',
        body: z.object({ token: z.string().min(1).max(4096) }),
        response: { 204: z.null() },
      },
    },
    async (req, reply) => {
      await app.notifications.unregisterDevice(req.auth.userId, req.body.token);
      return reply.code(204).send(null);
    },
  );
};

export default notificationRoutes;
