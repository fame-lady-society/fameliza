import type { Plugin, IAgentRuntime } from "@elizaos/core";
import type { Express, Request, Response } from "express";
import expressSession from "express-session";
import passport, { AuthenticatedRequest } from "./middleware/auth";
import { requireAuthOrApiKey } from "./middleware/apiKey";

const SESSION_SECRET = process.env.SESSION_SECRET || "change-me-in-production";

export const authPlugin: Plugin = {
  name: "auth",
  description: "Discord OAuth and API key authentication for Fameliza",

  async init(
    config: Record<string, string>,
    runtime: IAgentRuntime
  ): Promise<void> {
    try {
      const server = (runtime as any).server;
      if (!server || !server.app) {
        console.warn(
          "Server not available, skipping auth plugin initialization"
        );
        return;
      }

      const app = server.app as Express;

      app.use(
        expressSession({
          secret: SESSION_SECRET,
          resave: false,
          saveUninitialized: false,
          cookie: {
            secure: process.env.NODE_ENV === "production",
            httpOnly: true,
            maxAge: 24 * 60 * 60 * 1000,
          },
        })
      );

      app.use(passport.initialize());
      app.use(passport.session());

      app.use((req, res, next) => {
        if (
          req.path.startsWith("/api/") &&
          !req.path.startsWith("/api/auth") &&
          req.path !== "/health"
        ) {
          return requireAuthOrApiKey(req as AuthenticatedRequest, res, next);
        }
        if (req.path.startsWith("/auth") || req.path === "/health") {
          return next();
        }
        if (req.path.startsWith("/api/")) {
          return requireAuthOrApiKey(req as AuthenticatedRequest, res, next);
        }
        return next();
      });

      console.log("Auth plugin initialized");
    } catch (error) {
      console.error("Error initializing auth plugin:", error);
    }
  },

  routes: [
    {
      name: "discord-auth",
      path: "/auth/discord",
      type: "GET",
      handler: passport.authenticate("discord"),
    },
    {
      name: "discord-callback",
      path: "/auth/discord/callback",
      type: "GET",
      handler: async (req: Request, res: Response, runtime: IAgentRuntime) => {
        await passport.authenticate("discord", {
          failureRedirect: "/auth/failure",
        })(req, res, runtime);
        res.redirect("/");
      },
    },
    {
      name: "logout",
      path: "/auth/logout",
      type: "GET",
      handler: async (req: AuthenticatedRequest, res: Response) => {
        req.logout((err: unknown) => {
          if (err) {
            return res.status(500).json({ error: "Logout failed" });
          }
          res.redirect("/");
        });
      },
    },
    {
      name: "me",
      path: "/auth/me",
      type: "GET",
      handler: async (req: AuthenticatedRequest, res: Response) => {
        if (
          !req.isAuthenticated ||
          typeof req.isAuthenticated !== "function" ||
          !req.isAuthenticated()
        ) {
          res.status(401).json({ error: "Not authenticated" });
          return;
        }
        res.json({
          user: req.user,
          authenticated: true,
        });
      },
    },
    {
      name: "auth-failure",
      path: "/auth/failure",
      type: "GET",
      handler: async (_req: Request, res: Response) => {
        res.status(401).json({ error: "Authentication failed" });
      },
    },
    {
      name: "api-key",
      path: "/auth/api-key",
      type: "POST",
      handler: async (req: AuthenticatedRequest, res: Response) => {
        if (!req.isAuthenticated()) {
          res.status(401).json({ error: "Authentication required" });
          return;
        }
        try {
          const { generateApiKey } = await import("./middleware/apiKey");
          const apiKey = await generateApiKey(req.user?.id);
          res.json({ apiKey });
        } catch (error) {
          res.status(500).json({ error: "Failed to generate API key" });
        }
      },
    },
    {
      name: "health",
      path: "/health",
      type: "GET",
      handler: (_req: Request, res: Response) => {
        res.json({ status: "ok", timestamp: new Date().toISOString() });
      },
    },
  ],
};

export default authPlugin;
