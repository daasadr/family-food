import { PrismaClient } from '@prisma/client';
import type { FastifyPluginAsync } from 'fastify';
import fp from 'fastify-plugin';

declare module 'fastify' {
  interface FastifyInstance {
    prisma: PrismaClient;
  }
}

const prismaPlugin: FastifyPluginAsync = async (app) => {
  const prisma = new PrismaClient({
    log: app.log.level === 'debug' ? ['query', 'warn', 'error'] : ['warn', 'error'],
  });

  await prisma.$connect();
  app.decorate('prisma', prisma);

  app.addHook('onClose', async () => {
    await prisma.$disconnect();
  });
};

export default fp(prismaPlugin, { name: 'prisma' });
