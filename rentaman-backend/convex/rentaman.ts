import { mutation, query, QueryCtx } from "./_generated/server";
import { v } from "convex/values";

// ──────────────────────────────────────────────────────────────
//  HELPER: Verify API key and return userId (as string)
// ──────────────────────────────────────────────────────────────
async function requireUser(ctx: QueryCtx, apiKey: string): Promise<string> {
  if (!apiKey || apiKey.length < 32) throw new Error("Unauthorized");
  const user = await ctx.db
    .query("users")
    .withIndex("by_apiKey", (q) => q.eq("apiKey", apiKey))
    .unique();
  if (!user) throw new Error("Unauthorized");
  return user._id as unknown as string;
}

// ──────────────────────────────────────────────────────────────
//  PROPERTIES
// ──────────────────────────────────────────────────────────────

export const upsertProperty = mutation({
  args: {
    apiKey: v.string(),
    externalId: v.string(),
    name: v.string(),
    address: v.optional(v.string()),
    colorHex: v.string(),
    monthlyBudget: v.number(),
    isDefault: v.boolean(),
    updatedAt: v.number(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    const existing = await ctx.db
      .query("properties")
      .withIndex("by_externalId", (q) => q.eq("externalId", args.externalId))
      .unique();

    if (existing && (existing.ownerId as unknown as string) !== ownerId) {
      throw new Error("Unauthorized: not your property");
    }

    const data = {
      externalId: args.externalId,
      name: args.name,
      address: args.address,
      colorHex: args.colorHex,
      monthlyBudget: args.monthlyBudget,
      isDefault: args.isDefault,
      updatedAt: args.updatedAt,
      deleted: false,
      ownerId,
    };

    if (existing) {
      if (args.updatedAt <= existing.updatedAt) {
        return { status: "skipped", reason: "stale" };
      }
      await ctx.db.patch(existing._id, data);
      return { status: "updated" };
    }

    await ctx.db.insert("properties", data);
    return { status: "inserted" };
  },
});

export const deleteProperty = mutation({
  args: { apiKey: v.string(), externalId: v.string(), updatedAt: v.number() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const existing = await ctx.db
      .query("properties")
      .withIndex("by_externalId", (q) => q.eq("externalId", args.externalId))
      .unique();
    if (!existing) return { status: "not_found" };
    if ((existing.ownerId as unknown as string) !== ownerId)
      throw new Error("Unauthorized");
    await ctx.db.patch(existing._id, {
      deleted: true,
      updatedAt: args.updatedAt,
    });
    return { status: "deleted" };
  },
});

export const listProperties = query({
  args: { apiKey: v.string(), since: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const all = await ctx.db
      .query("properties")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    return all
      .filter((p) => !p.deleted)
      .filter((p) => (args.since ? p.updatedAt > args.since : true));
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS
// ──────────────────────────────────────────────────────────────

export const upsertBill = mutation({
  args: {
    apiKey: v.string(),
    externalId: v.string(),
    title: v.string(),
    amount: v.number(),
    categoryRawValue: v.string(),
    dueDate: v.number(),
    isPaid: v.boolean(),
    paymentDate: v.optional(v.number()),
    notes: v.optional(v.string()),
    receiptIdentifier: v.optional(v.string()),
    isRecurring: v.boolean(),
    recurringFrequencyRaw: v.string(),
    propertyExternalId: v.string(),
    updatedAt: v.number(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    const existing = await ctx.db
      .query("bills")
      .withIndex("by_externalId", (q) => q.eq("externalId", args.externalId))
      .unique();

    if (existing && (existing.ownerId as unknown as string) !== ownerId) {
      throw new Error("Unauthorized: not your bill");
    }

    const { apiKey, ...rest } = args;
    const data = { ...rest, deleted: false, ownerId };

    if (existing) {
      if (args.updatedAt <= existing.updatedAt) {
        return { status: "skipped", reason: "stale" };
      }
      await ctx.db.patch(existing._id, data);
      return { status: "updated" };
    }

    await ctx.db.insert("bills", data);
    return { status: "inserted" };
  },
});

export const deleteBill = mutation({
  args: { apiKey: v.string(), externalId: v.string(), updatedAt: v.number() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const existing = await ctx.db
      .query("bills")
      .withIndex("by_externalId", (q) => q.eq("externalId", args.externalId))
      .unique();
    if (!existing) return { status: "not_found" };
    if ((existing.ownerId as unknown as string) !== ownerId)
      throw new Error("Unauthorized");
    await ctx.db.patch(existing._id, {
      deleted: true,
      updatedAt: args.updatedAt,
    });
    return { status: "deleted" };
  },
});

export const listBills = query({
  args: {
    apiKey: v.string(),
    since: v.optional(v.number()),
    propertyExternalId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const all = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    return all
      .filter((b) => !b.deleted)
      .filter((b) => (args.since ? b.updatedAt > args.since : true))
      .filter((b) =>
        args.propertyExternalId
          ? b.propertyExternalId === args.propertyExternalId
          : true,
      );
  },
});
