import { mutation, query, QueryCtx } from "./_generated/server";
import { v } from "convex/values";

// ──────────────────────────────────────────────────────────────
//  HELPER
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
//  PROPERTIES — single upsert
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
//  PROPERTIES — single delete
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
//  PROPERTIES — batch upsert
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
//  PROPERTIES — batch delete
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

// ──────────────────────────────────────────────────────────────
//  BILLS — batch upsert  (all fields incl. isDeleted + deletedAt)
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
      isPaused?: boolean;
      paymentMethodRaw?: string;
      isDeleted?: boolean;
      deletedAt?: number;
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
        isPaused: item.isPaused ?? false,
        paymentMethodRaw: item.paymentMethodRaw,
        deleted: item.isDeleted ?? false,
        deletedAt: item.deletedAt,
        propertyExternalId: item.propertyExternalId,
        updatedAt: item.updatedAt,
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
//  BILLS — batch delete (permanent tombstone)
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
        deletedAt: args.updatedAt,
        updatedAt: args.updatedAt,
      });
      deleted++;
    }
    return { deleted, skipped };
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS — single upsert (with isDeleted + deletedAt)
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
    isPaused: v.optional(v.boolean()),
    paymentMethodRaw: v.optional(v.string()),
    isDeleted: v.optional(v.boolean()),
    deletedAt: v.optional(v.number()),
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

    const { apiKey, isDeleted, ...rest } = args;
    const data = {
      ...rest,
      isPaused: rest.isPaused ?? false,
      deleted: isDeleted ?? false,
      deletedAt: rest.deletedAt,
      ownerId,
    };

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
//  BILLS — single delete (soft)
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
      deletedAt: args.updatedAt,
      updatedAt: args.updatedAt,
    });
    return { status: "deleted" };
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS — restore
// ──────────────────────────────────────────────────────────────
export const restoreBill = mutation({
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
      deleted: false,
      deletedAt: undefined,
      updatedAt: args.updatedAt,
    });
    return { status: "restored" };
  },
});

// ──────────────────────────────────────────────────────────────
//  BILLS — list (excludes soft-deleted by default)
// ──────────────────────────────────────────────────────────────
export const listBills = query({
  args: {
    apiKey: v.string(),
    since: v.optional(v.number()),
    propertyExternalId: v.optional(v.string()),
    includeDeleted: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const all = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    return all
      .filter((b) => (args.includeDeleted ? true : !b.deleted))
      .filter((b) => (args.since ? b.updatedAt > args.since : true))
      .filter((b) =>
        args.propertyExternalId
          ? b.propertyExternalId === args.propertyExternalId
          : true,
      );
  },
});

// ──────────────────────────────────────────────────────────────
//  MIGRATION — Backfill isPaused = false
// ──────────────────────────────────────────────────────────────
export const migrationBackfillIsPaused = mutation({
  args: { apiKey: v.string() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const allBills = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    let patched = 0,
      alreadySet = 0;
    const now = Date.now();
    for (const bill of allBills) {
      if (bill.isPaused !== undefined && bill.isPaused !== null) {
        alreadySet++;
        continue;
      }
      await ctx.db.patch(bill._id, { isPaused: false, updatedAt: now });
      patched++;
    }
    return { totalBills: allBills.length, patched, alreadySet };
  },
});

// ──────────────────────────────────────────────────────────────
//  MIGRATION — Paid bills → "Cash"
// ──────────────────────────────────────────────────────────────
export const migrationPaidBillsToCash = mutation({
  args: { apiKey: v.string() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const allBills = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    const now = Date.now();
    let convertedToCash = 0,
      alreadyCash = 0,
      keptExplicitMethod = 0,
      unpaidFilledWithOther = 0;
    for (const bill of allBills) {
      const current = bill.paymentMethodRaw;
      if (bill.isPaid) {
        if (current === undefined || current === null || current === "Other") {
          await ctx.db.patch(bill._id, {
            paymentMethodRaw: "Cash",
            updatedAt: now,
          });
          convertedToCash++;
        } else if (current === "Cash") {
          alreadyCash++;
        } else {
          keptExplicitMethod++;
        }
      } else if (current === undefined || current === null) {
        await ctx.db.patch(bill._id, {
          paymentMethodRaw: "Other",
          updatedAt: now,
        });
        unpaidFilledWithOther++;
      }
    }
    return {
      totalBills: allBills.length,
      convertedToCash,
      alreadyCash,
      keptExplicitMethod,
      unpaidFilledWithOther,
    };
  },
});

// ──────────────────────────────────────────────────────────────
//  DIAGNOSTIC — Payment methods
// ──────────────────────────────────────────────────────────────
export const diagnosticsPaymentMethods = query({
  args: { apiKey: v.string() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const allBills = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    const counts: Record<string, number> = {};
    let paidMissing = 0,
      unpaidMissing = 0;
    for (const bill of allBills) {
      const current = bill.paymentMethodRaw;
      if (current === undefined || current === null) {
        if (bill.isPaid) paidMissing++;
        else unpaidMissing++;
      } else {
        const key = bill.isPaid ? `paid:${current}` : `unpaid:${current}`;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return {
      totalBills: allBills.length,
      paidMissingPaymentMethod: paidMissing,
      unpaidMissingPaymentMethod: unpaidMissing,
      countsByPaidState: counts,
    };
  },
});

// ──────────────────────────────────────────────────────────────
//  DIAGNOSTIC — Paused recurring bills
// ──────────────────────────────────────────────────────────────
export const diagnosticsPausedBills = query({
  args: { apiKey: v.string() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const allBills = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    let recurringActive = 0,
      recurringPaused = 0,
      recurringMissingFlag = 0;
    for (const bill of allBills) {
      if (!bill.isRecurring) continue;
      if (bill.isPaused === undefined || bill.isPaused === null)
        recurringMissingFlag++;
      else if (bill.isPaused) recurringPaused++;
      else recurringActive++;
    }
    return {
      totalBills: allBills.length,
      recurringActive,
      recurringPaused,
      recurringMissingFlag,
    };
  },
});

// ──────────────────────────────────────────────────────────────
//  DIAGNOSTIC — Soft delete state
// ──────────────────────────────────────────────────────────────
export const diagnosticsDeletedBills = query({
  args: { apiKey: v.string() },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);
    const all = await ctx.db
      .query("bills")
      .withIndex("by_owner", (q) => q.eq("ownerId", ownerId))
      .collect();
    let live = 0,
      deleted = 0,
      deletedMissingTimestamp = 0;
    for (const b of all) {
      if (b.deleted) {
        deleted++;
        if (b.deletedAt === undefined || b.deletedAt === null)
          deletedMissingTimestamp++;
      } else live++;
    }
    return { totalBills: all.length, live, deleted, deletedMissingTimestamp };
  },
});

// ──────────────────────────────────────────────────────────────
//  MIGRATION — Fix property references
// ──────────────────────────────────────────────────────────────
export const migrationFixPropertyRefs = mutation({
  args: {
    apiKey: v.string(),
    targetPropertyExternalId: v.string(),
  },
  handler: async (ctx, args) => {
    const ownerId = await requireUser(ctx, args.apiKey);

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
