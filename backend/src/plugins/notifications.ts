import type { FastifyPluginAsync } from 'fastify';
import fp from 'fastify-plugin';

import { createPushSender, type PushSender } from '../modules/notifications/fcm.js';
import { NotificationService } from '../modules/notifications/service.js';

declare module 'fastify' {
  interface FastifyInstance {
    notifications: NotificationService;
  }
}

export interface NotificationsPluginOptions {
  /** Testy sem podstrčí vlastní odesílač místo skutečného FCM. */
  sender?: PushSender | null;
}

const notificationsPlugin: FastifyPluginAsync<NotificationsPluginOptions> = async (
  app,
  opts,
) => {
  const sender =
    opts.sender !== undefined ? opts.sender : createPushSender(app.log);

  if (!sender) {
    app.log.info('FCM není nastavené — push notifikace se odesílat nebudou.');
  }

  app.decorate('notifications', new NotificationService(app.prisma, sender, app.log));
};

export default fp(notificationsPlugin, { name: 'notifications', dependencies: ['prisma'] });
