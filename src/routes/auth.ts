import type { Express } from 'express';
import passport from '../middleware/auth';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { generateApiKey } from '../middleware/apiKey';

export const setupAuthRoutes = (app: Express): void => {
  app.get('/auth/discord', passport.authenticate('discord'));
  
  app.get(
    '/auth/discord/callback',
    passport.authenticate('discord', { failureRedirect: '/auth/failure' }),
    (req: AuthenticatedRequest, res) => {
      res.redirect('/');
    }
  );
  
  app.get('/auth/logout', (req: AuthenticatedRequest, res) => {
    req.logout((err) => {
      if (err) {
        return res.status(500).json({ error: 'Logout failed' });
      }
      res.redirect('/');
    });
  });
  
  app.get('/auth/me', requireAuth, (req: AuthenticatedRequest, res) => {
    res.json({
      user: req.user,
      authenticated: true,
    });
  });
  
  app.get('/auth/failure', (req, res) => {
    res.status(401).json({ error: 'Authentication failed' });
  });
  
  app.post('/auth/api-key', requireAuth, async (req: AuthenticatedRequest, res) => {
    try {
      const apiKey = await generateApiKey(req.user?.id);
      res.json({ apiKey });
    } catch (error) {
      res.status(500).json({ error: 'Failed to generate API key' });
    }
  });
  
  app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });
};

