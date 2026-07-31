import { defineConfig } from 'vitest/config';

// Testy běží proti samostatné databázi family_food_test, aby nemazaly vývojová data.
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL =
  process.env.TEST_DATABASE_URL ??
  'postgresql://familyfood:familyfood@localhost:5432/family_food_test?schema=public';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    environment: 'node',
    globals: false,
    testTimeout: 30_000,
    hookTimeout: 30_000,
    // Testy sdílí jednu DB — paralelní soubory by si lezly do zelí.
    fileParallelism: false,
  },
});
