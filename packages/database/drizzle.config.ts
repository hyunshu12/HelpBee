import { defineConfig } from 'drizzle-kit';

const DEFAULT_URL = 'postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee';

export default defineConfig({
  schema: './src/schema/*',
  out: './migrations',
  driver: 'pg',
  dbCredentials: {
    connectionString: process.env.DATABASE_URL || DEFAULT_URL,
  },
  strict: true,
  verbose: true,
});
