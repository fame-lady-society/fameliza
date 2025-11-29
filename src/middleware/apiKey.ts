import type { Request, Response, NextFunction } from "express";
import bcrypt from "bcrypt";
import { AuthenticatedRequest } from "./auth";

const API_KEY_SECRET = process.env.API_KEY_SECRET || "";

interface ApiKeyRecord {
  keyHash: string;
  userId?: string;
  createdAt: Date;
  lastUsed?: Date;
}

const apiKeys: Map<string, ApiKeyRecord> = new Map();

export const generateApiKey = async (userId?: string): Promise<string> => {
  const crypto = await import("crypto");
  const key = `fameliza_${crypto.randomBytes(32).toString("hex")}`;
  const hash = await bcrypt.hash(key, 10);

  apiKeys.set(key, {
    keyHash: hash,
    userId,
    createdAt: new Date(),
  });

  return key;
};

export const validateApiKey = async (key: string): Promise<boolean> => {
  for (const [storedKey, record] of apiKeys.entries()) {
    if (await bcrypt.compare(key, record.keyHash)) {
      record.lastUsed = new Date();
      return true;
    }
  }
  return false;
};

export const requireApiKey = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res
      .status(401)
      .json({
        error: "API key required. Use Authorization: Bearer <key> header",
      });
    return;
  }

  const apiKey = authHeader.substring(7);
  const isValid = await validateApiKey(apiKey);

  if (!isValid) {
    res.status(401).json({ error: "Invalid API key" });
    return;
  }

  next();
};

export const requireAuthOrApiKey = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): Promise<void> => {
  if (
    req.isAuthenticated &&
    typeof req.isAuthenticated === "function" &&
    req.isAuthenticated()
  ) {
    return next();
  }

  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith("Bearer ")) {
    const apiKey = authHeader.substring(7);
    const isValid = await validateApiKey(apiKey);
    if (isValid) {
      return next();
    }
  }

  res.status(401).json({ error: "Authentication or valid API key required" });
};
