import { Hono } from 'hono';

const app = new Hono();

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// API routes will be imported here
// import authRoutes from './routes/auth';
// import hivesRoutes from './routes/hives';
// import analysesRoutes from './routes/analyses';

// app.route('/api/auth', authRoutes);
// app.route('/api/hives', hivesRoutes);
// app.route('/api/analyses', analysesRoutes);

const port = parseInt(process.env.PORT || '3001', 10);

console.log(`🚀 API Server is running on http://localhost:${port}`);

export default app;
