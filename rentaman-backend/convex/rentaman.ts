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
//  PROPERTIES — single upsert (kept for compatibility)
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
      if (args.updatedAt <= existing.updatedAt)
        return { status: "skipped", reason: "stale" };
      await ctx.db.patch(existing._id, data);
      return { status: "updated" };
    }
    await ctx.db.insert("properties", data);
    return { status: "inserted" };
  },
});

// ──────────────────────────────────────────────────────────────
//  PROPERTIES — single delete (kept for compatibility)
// ──────────────────────────────────────────────────────────────
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

// ──────────────────────────────────────────────────────────────
//  PROPERTIES — batch upsert (JSON payload)
// ──────────────────────────────────────────────────────────────
export const batchUpsertProperties = mutation({
  args: {
    apiKey: v.string(),
    itemsJson: v.string(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    type Item = {
      externalId: string;
      name: string;
      address?: string;
      colorHex: string;
      monthlyBudget: number;
      isDefault: boolean;
      updatedAt: number;
    };

    let items: Item[];
    try {
      items = JSON.parse(args.itemsJson) as Item[];
    } catch {
      throw new Error("Invalid itemsJson");
    }

    let inserted = 0,
      updated = 0,
      skipped = 0;

    for (const item of items) {
      const existing = await ctx.db
        .query("properties")
        .withIndex("by_externalId", (q) => q.eq("externalId", item.externalId))
        .unique();

      if (existing && (existing.ownerId as unknown as string) !== ownerId) {
        skipped++;
        continue;
      }

      const data = {
        externalId: item.externalId,
        name: item.name,
        address: item.address,
        colorHex: item.colorHex,
        monthlyBudget: item.monthlyBudget,
        isDefault: item.isDefault,
        updatedAt: item.updatedAt,
        deleted: false,
        ownerId,
      };

      if (existing) {
        if (item.updatedAt <= existing.updatedAt) {
          skipped++;
          continue;
        }
        await ctx.db.patch(existing._id, data);
        updated++;
      } else {
        await ctx.db.insert("properties", data);
        inserted++;
      }
    }
    return { inserted, updated, skipped };
  },
});

// ──────────────────────────────────────────────────────────────
//  PROPERTIES — batch delete (JSON payload)
// ──────────────────────────────────────────────────────────────
export const batchDeleteProperties = mutation({
  args: {
    apiKey: v.string(),
    externalIdsJson: v.string(),
    updatedAt: v.number(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    let externalIds: string[];
    try {
      externalIds = JSON.parse(args.externalIdsJson) as string[];
    } catch {
      throw new Error("Invalid externalIdsJson");
    }

    let deleted = 0,
      skipped = 0;
    for (const extId of externalIds) {
      const existing = await ctx.db
        .query("properties")
        .withIndex("by_externalId", (q) => q.eq("externalId", extId))
        .unique();
      if (!existing) {
        skipped++;
        continue;
      }
      if ((existing.ownerId as unknown as string) !== ownerId) {
        skipped++;
        continue;
      }
      await ctx.db.patch(existing._id, {
        deleted: true,
        updatedAt: args.updatedAt,
      });
      deleted++;
    }
    return { deleted, skipped };
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS — batch upsert (JSON payload)
// ──────────────────────────────────────────────────────────────
export const batchUpsertBills = mutation({
  args: {
    apiKey: v.string(),
    itemsJson: v.string(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    type Item = {
      externalId: string;
      title: string;
      amount: number;
      categoryRawValue: string;
      dueDate: number;
      isPaid: boolean;
      paymentDate?: number;
      notes?: string;
      receiptIdentifier?: string;
      isRecurring: boolean;
      recurringFrequencyRaw: string;
      propertyExternalId: string;
      updatedAt: number;
    };

    let items: Item[];
    try {
      items = JSON.parse(args.itemsJson) as Item[];
    } catch {
      throw new Error("Invalid itemsJson");
    }

    let inserted = 0,
      updated = 0,
      skipped = 0;

    for (const item of items) {
      const existing = await ctx.db
        .query("bills")
        .withIndex("by_externalId", (q) => q.eq("externalId", item.externalId))
        .unique();

      if (existing && (existing.ownerId as unknown as string) !== ownerId) {
        skipped++;
        continue;
      }

      const data = {
        externalId: item.externalId,
        title: item.title,
        amount: item.amount,
        categoryRawValue: item.categoryRawValue,
        dueDate: item.dueDate,
        isPaid: item.isPaid,
        paymentDate: item.paymentDate,
        notes: item.notes,
        receiptIdentifier: item.receiptIdentifier,
        isRecurring: item.isRecurring,
        recurringFrequencyRaw: item.recurringFrequencyRaw,
        propertyExternalId: item.propertyExternalId,
        updatedAt: item.updatedAt,
        deleted: false,
        ownerId,
      };

      if (existing) {
        if (item.updatedAt <= existing.updatedAt) {
          skipped++;
          continue;
        }
        await ctx.db.patch(existing._id, data);
        updated++;
      } else {
        await ctx.db.insert("bills", data);
        inserted++;
      }
    }
    return { inserted, updated, skipped };
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS — batch delete (JSON payload)
// ──────────────────────────────────────────────────────────────
export const batchDeleteBills = mutation({
  args: {
    apiKey: v.string(),
    externalIdsJson: v.string(),
    updatedAt: v.number(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    let externalIds: string[];
    try {
      externalIds = JSON.parse(args.externalIdsJson) as string[];
    } catch {
      throw new Error("Invalid externalIdsJson");
    }

    let deleted = 0,
      skipped = 0;
    for (const extId of externalIds) {
      const existing = await ctx.db
        .query("bills")
        .withIndex("by_externalId", (q) => q.eq("externalId", extId))
        .unique();
      if (!existing) {
        skipped++;
        continue;
      }
      if ((existing.ownerId as unknown as string) !== ownerId) {
        skipped++;
        continue;
      }
      await ctx.db.patch(existing._id, {
        deleted: true,
        updatedAt: args.updatedAt,
      });
      deleted++;
    }
    return { deleted, skipped };
  },
});

// ──────────────────────────────────────────────────────────────
//  PROPERTIES — list
// ──────────────────────────────────────────────────────────────
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
//  BILLS — single upsert (kept for compatibility)
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
      if (args.updatedAt <= existing.updatedAt)
        return { status: "skipped", reason: "stale" };
      await ctx.db.patch(existing._id, data);
      return { status: "updated" };
    }
    await ctx.db.insert("bills", data);
    return { status: "inserted" };
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS — single delete (kept for compatibility)
// ──────────────────────────────────────────────────────────────
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

// ──────────────────────────────────────────────────────────────
//  BILLS — list
// ──────────────────────────────────────────────────────────────
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

// ──────────────────────────────────────────────────────────────
//  PROPERTIES — fetch one by externalId
// ──────────────────────────────────────────────────────────────
export const getPropertyByExternalId = query({
  args: { apiKey: v.string(), externalId: v.string() },
  handler: async (ctx, args) => {
    await requireUser(ctx, args.apiKey);
    const prop = await ctx.db
      .query("properties")
      .withIndex("by_externalId", (q) => q.eq("externalId", args.externalId))
      .unique();
    return prop ?? null;
  },
});

//  ONE-TIME MIGRATION
//  Repoints every bill in your account to the correct property.
//  Safe to run multiple times — idempotent.
//  Delete this function after the migration succeeds.
// ──────────────────────────────────────────────────────────────
export const migrationFixPropertyRefs = mutation({
  args: {
    apiKey: v.string(),
    targetPropertyExternalId: v.string(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

    // 1. Confirm the target property exists and belongs to this user.
    const target = await ctx.db
      .query("properties")
      .withIndex("by_externalId", (q) =>
        q.eq("externalId", args.targetPropertyExternalId),
      )
      .unique();

    if (!target) {
      throw new Error(
        `Target property ${args.targetPropertyExternalId} not found`,
      );
    }
    if ((target.ownerId as unknown as string) !== ownerId) {
      throw new Error("Target property belongs to a different owner");
    }

    // 2. Repoint every bill belonging to this user.
    const allBills = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();

    let patched = 0;
    let alreadyCorrect = 0;
    const now = Date.now();

    for (const bill of allBills) {
      if (bill.propertyExternalId === args.targetPropertyExternalId) {
        alreadyCorrect++;
        continue;
      }
      await ctx.db.patch(bill._id, {
        propertyExternalId: args.targetPropertyExternalId,
        updatedAt: now,
      });
      patched++;
    }

    return {
      totalBills: allBills.length,
      patched,
      alreadyCorrect,
      targetProperty: target.name,
    };
  },
});
