import { env } from './config/env.js';
import { buildServer } from './server.js';

const app = await buildServer();

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, async () => {
    app.log.info(`Přijat ${signal}, ukončuji server…`);
    await app.close();
    process.exit(0);
  });
}

try {
  await app.listen({ port: env.PORT, host: env.HOST });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
