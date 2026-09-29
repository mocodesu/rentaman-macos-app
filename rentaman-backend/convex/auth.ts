import { action, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { api } from "./_generated/api";
import { hashPassword, generateApiKey, generateSalt } from "./passwords";

// ──────────────────────────────────────────────────────────────
//  SIGN UP
// ──────────────────────────────────────────────────────────────
export const signUp = action({
  args: {
    email: v.string(),
    password: v.string(),
    name: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<{ apiKey: string }> => {
    const email = args.email.trim().toLowerCase();

    // Validate
    if (!email.includes("@")) throw new Error("Invalid email");
    if (args.password.length < 8)
      throw new Error("Password must be at least 8 characters");

    // Check if user exists
    const existing = await ctx.runQuery(api.auth.findUserByEmail, { email });
    if (existing) throw new Error("An account with this email already exists");

    // Generate credentials
    const salt = generateSalt();
    const passwordHash = await hashPassword(args.password, salt);
    const apiKey = generateApiKey();

    await ctx.runMutation(api.auth.createUser, {
      email,
      passwordHash: `${salt}:${passwordHash}`,
      apiKey,
      name: args.name,
    });

    return { apiKey };
  },
});

// ──────────────────────────────────────────────────────────────
//  SIGN IN
// ──────────────────────────────────────────────────────────────
export const signIn = action({
  args: {
    email: v.string(),
    password: v.string(),
  },
  handler: async (ctx, args): Promise<{ apiKey: string }> => {
    const email = args.email.trim().toLowerCase();
    const user = await ctx.runQuery(api.auth.findUserByEmail, { email });
    if (!user) throw new Error("Invalid email or password");

    const [salt, storedHash] = user.passwordHash.split(":");
    const attemptHash = await hashPassword(args.password, salt);
    if (attemptHash !== storedHash)
      throw new Error("Invalid email or password");

    return { apiKey: user.apiKey };
  },
});

// ──────────────────────────────────────────────────────────────
//  ME (verify API key, return user)
// ──────────────────────────────────────────────────────────────
export const me = query({
  args: { apiKey: v.string() },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_apiKey", (q) => q.eq("apiKey", args.apiKey))
      .unique();
    if (!user) return null;
    return {
      _id: user._id,
      email: user.email,
      name: user.name ?? null,
    };
  },
});

// ──────────────────────────────────────────────────────────────
//  INTERNAL — called from actions, not exposed to clients
// ──────────────────────────────────────────────────────────────
export const findUserByEmail = query({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    return await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.email))
      .unique();
  },
});

export const createUser = mutation({
  args: {
    email: v.string(),
    passwordHash: v.string(),
    apiKey: v.string(),
    name: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return await ctx.db.insert("users", {
      email: args.email,
      passwordHash: args.passwordHash,
      apiKey: args.apiKey,
      name: args.name,
      createdAt: Date.now(),
    });
  },
});
