import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  users: defineTable({
    email: v.string(),
    passwordHash: v.string(),
    apiKey: v.string(),
    name: v.optional(v.string()),
    createdAt: v.number(),
  })
    .index("by_email", ["email"])
    .index("by_apiKey", ["apiKey"]),

  properties: defineTable({
    externalId: v.string(),
    name: v.string(),
    address: v.optional(v.string()),
    colorHex: v.string(),
    monthlyBudget: v.number(),
    isDefault: v.boolean(),
    updatedAt: v.number(),
    deleted: v.boolean(),
    ownerId: v.optional(v.string()),
  })
    .index("by_externalId", ["externalId"])
    .index("by_owner", ["ownerId"]),

  bills: defineTable({
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
    deleted: v.boolean(),
    deletedAt: v.optional(v.number()),
    propertyExternalId: v.string(),
    updatedAt: v.number(),
    ownerId: v.optional(v.string()),
  })
    .index("by_externalId", ["externalId"])
    .index("by_property", ["propertyExternalId"])
    .index("by_owner", ["ownerId"])
    .index("by_updatedAt", ["updatedAt"]),
});
