import type { Request, Response, NextFunction } from "express";
import passport from "passport";
import { Strategy as DiscordStrategy } from "passport-discord";

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    username: string;
    discriminator: string;
    avatar: string | null;
    email?: string;
    guilds?: Array<{ id: string; roles?: string[] }>;
  };
}

const DISCORD_CLIENT_ID = process.env.DISCORD_CLIENT_ID || "";
const DISCORD_CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || "";
const DISCORD_CALLBACK_URL =
  process.env.DISCORD_CALLBACK_URL ||
  "https://ai.fame.support/auth/discord/callback";
const ALLOWED_USER_IDS =
  process.env.ALLOWED_DISCORD_USER_IDS?.split(",").map((id) => id.trim()) || [];
const ALLOWED_GUILD_ROLES =
  process.env.ALLOWED_DISCORD_GUILD_ROLES?.split(",").map((role) =>
    role.trim()
  ) || [];

if (DISCORD_CLIENT_ID && DISCORD_CLIENT_SECRET) {
  passport.use(
    new DiscordStrategy(
      {
        clientID: DISCORD_CLIENT_ID,
        clientSecret: DISCORD_CLIENT_SECRET,
        callbackURL: DISCORD_CALLBACK_URL,
        scope: ["identify", "email", "guilds"],
      },
      async (accessToken: string, refreshToken: string, profile, done) => {
        try {
          const user = {
            id: profile.id,
            username: profile.username,
            discriminator: profile.discriminator,
            avatar: profile.avatar,
            email: profile.email,
            guilds: profile.guilds || [],
          };

          if (
            ALLOWED_USER_IDS.length > 0 &&
            !ALLOWED_USER_IDS.includes(user.id)
          ) {
            return done(new Error("User not authorized"));
          }

          if (ALLOWED_GUILD_ROLES.length > 0) {
            const hasRequiredRole = user.guilds.some((guild: any) =>
              ALLOWED_GUILD_ROLES.some((role) => guild.roles?.includes(role))
            );
            if (!hasRequiredRole) {
              return done(new Error("User does not have required role"));
            }
          }

          return done(null, user);
        } catch (error) {
          return done(error, false);
        }
      }
    )
  );

  passport.serializeUser((user, done) => {
    done(null, user);
  });

  passport.deserializeUser((user, done) => {
    done(null, user as any);
  });
}

export const requireAuth = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  if (req.isAuthenticated()) {
    return next();
  }
  res.status(401).json({ error: "Authentication required" });
};

export const optionalAuth = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  next();
};

export default passport;
