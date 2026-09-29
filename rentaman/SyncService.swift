import Foundation
import SwiftData
import Observation
import Combine
import ConvexMobile

// MARK: - Sync Status
enum SyncState: Equatable {
    case localOnly
    case idle
    case syncing
    case live
    case error(String)

    var icon: String {
        switch self {
        case .localOnly: return "internaldrive"
        case .idle: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .live: return "dot.radiowaves.left.and.right"
        case .error: return "exclamationmark.icloud"
        }
    }
    var color: String {
        switch self {
        case .localOnly: return "gray"
        case .idle: return "green"
        case .syncing: return "blue"
        case .live: return "green"
        case .error: return "red"
        }
    }
    var label: String {
        switch self {
        case .localOnly: return "Local Only"
        case .idle: return "Synced"
        case .syncing: return "Syncing…"
        case .live: return "Live"
        case .error(let msg): return "Sync error: \(msg)"
        }
    }
}

// MARK: - Batch Response
struct BatchMutationResponse: Decodable {
    let inserted: Int?
    let updated: Int?
    let skipped: Int?
    let deleted: Int?
}

// MARK: - Publisher → async/await Bridge
extension Publisher {
    func firstValue() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var hasResumed = false
            cancellable = self.first().sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion, !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    } else if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: value)
                    }
                    cancellable?.cancel()
                }
            )
        }
    }
}

// MARK: - Sync Service
@Observable
final class SyncService {

    // ── Public state ──
    var state: SyncState = .localOnly
    var lastSyncAt: Date? = nil
    var pendingCount: Int = 0
    var lastError: String? = nil
    var isLive: Bool = false

    // ── Dependencies ──
    private var modelContext: ModelContext?
    private var client: ConvexClient?
    private var apiKey: String?

    // ── Tasks ──
    private var pushTask: Task<Void, Never>?
    private var incomingTask: Task<Void, Never>?

    // ── Subscriptions ──
    private var propertiesSubscription: AnyCancellable?
    private var billsSubscription: AnyCancellable?

    // ── Incoming coalescing ──
    private var incomingProperties: [RemoteProperty]?
    private var incomingBills: [RemoteBill]?

    // ── Orphan bills ──
    private var orphanBills: [RemoteBill] = []

    // ── Pending server-side deletes ──
    private var pendingBillDeletes: Set<String> = []
    private var pendingPropertyDeletes: Set<String> = []

    // ── Retry ──
    private var retryAttempt: Int = 0

    // ── Tunables ──
    private let pushDebounceSeconds: TimeInterval = 5.0
    private let incomingCoalesceNanos: UInt64 = 250_000_000

    static let shared = SyncService()
    private init() {}

    // MARK: - Setup
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        if !ConvexConfig.isConfigured { state = .localOnly }
    }

    func configureWithAuth(apiKey: String) {
        self.apiKey = apiKey
        guard ConvexConfig.isConfigured,
              let urlString = ConvexConfig.deploymentUrl,
              let url = URL(string: urlString) else {
            state = .localOnly
            return
        }
        if client == nil {
            self.client = ConvexClient(deploymentUrl: url.absoluteString)
        }

        startRealtimeSubscriptions()

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.pushLocalChanges()
        }
    }

    func reset() {
        stopRealtimeSubscriptions()
        apiKey = nil
        state = .localOnly
        pendingCount = 0
        lastSyncAt = nil
        lastError = nil
        isLive = false
        orphanBills.removeAll()
        pendingBillDeletes.removeAll()
        pendingPropertyDeletes.removeAll()
        incomingProperties = nil
        incomingBills = nil
        pushTask?.cancel(); pushTask = nil
        incomingTask?.cancel(); incomingTask = nil
    }

    @MainActor
    func requestRepair() {
        print("🔧 [Sync] Requesting repair — will reprocess next incoming payload")
        Task { await forceSync() }
    }

    // MARK: - Subscriptions
    private func startRealtimeSubscriptions() {
        guard let client = client, let apiKey = apiKey else { return }
        guard propertiesSubscription == nil, billsSubscription == nil else { return }

        print("📡 [Sync] Starting live subscriptions")

        let args: [String: ConvexEncodable?] = ["apiKey": apiKey]

        propertiesSubscription = client
            .subscribe(to: "rentaman:listProperties", with: args, yielding: [RemoteProperty].self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let err) = completion {
                        print("❌ [Sync] Properties stream failed: \(err)")
                        self.propertiesSubscription = nil
                        self.isLive = false
                        self.state = .error("Live properties stream failed")
                        self.scheduleSubscriptionRetry()
                    }
                },
                receiveValue: { [weak self] props in
                    self?.handlePropertiesPayload(props)
                }
            )

        billsSubscription = client
            .subscribe(to: "rentaman:listBills", with: args, yielding: [RemoteBill].self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    if case .failure(let err) = completion {
                        print("❌ [Sync] Bills stream failed: \(err)")
                        self.billsSubscription = nil
                        self.isLive = false
                        self.state = .error("Live bills stream failed")
                        self.scheduleSubscriptionRetry()
                    }
                },
                receiveValue: { [weak self] bills in
                    self?.handleBillsPayload(bills)
                }
            )
    }

    private func stopRealtimeSubscriptions() {
        propertiesSubscription?.cancel(); propertiesSubscription = nil
        billsSubscription?.cancel();     billsSubscription = nil
        isLive = false
    }

    private func scheduleSubscriptionRetry() {
        guard apiKey != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self = self, self.apiKey != nil else { return }
            if self.propertiesSubscription == nil || self.billsSubscription == nil {
                self.startRealtimeSubscriptions()
            }
        }
    }

    // MARK: - Incoming coalescing
    private func handlePropertiesPayload(_ props: [RemoteProperty]) {
        print("📡 [Sync] Received \(props.count) properties from stream")
        incomingProperties = props
        scheduleIncomingProcessing()
    }

    private func handleBillsPayload(_ bills: [RemoteBill]) {
        print("📡 [Sync] Received \(bills.count) bills from stream")
        incomingBills = bills
        scheduleIncomingProcessing()
    }

    private func scheduleIncomingProcessing() {
        incomingTask?.cancel()
        incomingTask = Task { [weak self] in
            let nanos = self?.incomingCoalesceNanos ?? 250_000_000
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await self?.processIncomingPayloads()
        }
    }

    @MainActor
    private func processIncomingPayloads() async {
        guard let context = modelContext else { return }

        // 1. Properties first — insert/update and COMMIT so bills can query them.
        if let props = incomingProperties {
            incomingProperties = nil
            for prop in props { _ = upsertLocalProperty(prop, context: context) }
            try? context.save()
        }

        // 2. Bills.
        if let bills = incomingBills {
            incomingBills = nil
            for bill in bills { upsertLocalBill(bill, context: context) }
        }

        // 3. Retry orphans (may need to fetch properties from server).
        await retryOrphanBills(context: context)

        try? context.save()
        lastSyncAt = Date()

        if !isLive, propertiesSubscription != nil, billsSubscription != nil {
            isLive = true
            if state != .syncing { state = .live }
        }
    }

    /// Handles bills whose `propertyExternalId` didn't resolve locally.
    /// 1. Tries again against local store (in case props just landed).
    /// 2. Falls back to a one-shot server fetch per unique property ID.
    /// 3. Anything still missing goes back into the orphan queue.
    @MainActor
    private func retryOrphanBills(context: ModelContext) async {
        guard !orphanBills.isEmpty else { return }

        let pending = orphanBills
        orphanBills.removeAll()

        // Group by property id so we don't fetch the same property N times.
        let grouped = Dictionary(grouping: pending, by: { $0.propertyExternalId })

        var resolved: [String: Property] = [:]

        for (propId, _) in grouped {
            // 1. Local hit?
            if let local = findProperty(id: propId, context: context) {
                resolved[propId] = local
                continue
            }
            // 2. Server fetch on demand.
            if let remote = await fetchPropertyFromServer(id: propId) {
                let newLocal = upsertLocalProperty(remote, context: context)
                resolved[propId] = newLocal
                try? context.save()
                print("✅ [Sync] On-demand fetched property \(propId) from server")
                continue
            }
            // 3. Still missing — log for diagnostics.
            let localIds = (try? context.fetch(FetchDescriptor<Property>()))?.map { $0.id } ?? []
            print("❌ [Sync] Property \(propId) not found locally (\(localIds.count) local props: \(localIds)) nor on server")
        }

        // Retry the bills with whatever properties we managed to resolve.
        for (propId, bills) in grouped {
            guard resolved[propId] != nil else {
                // Re-queue for next cycle.
                for bill in bills { orphanBills.append(bill) }
                continue
            }
            for bill in bills {
                upsertLocalBill(bill, context: context)
            }
        }
    }

    /// One-shot fetch of a single property from Convex by external ID.
    private func fetchPropertyFromServer(id: String) async -> RemoteProperty? {
        guard let client = client, let apiKey = apiKey else { return nil }
        let args: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
            "externalId": id,
        ]
        do {
            let publisher = client.subscribe(
                to: "rentaman:getPropertyByExternalId",
                with: args,
                yielding: RemoteProperty?.self
            )
            return try await publisher.firstValue()
        } catch {
            print("❌ [Sync] Server fetch for property \(id) failed: \(error)")
            return nil
        }
    }

    // MARK: - Manual triggers
    func schedulePush() {
        guard apiKey != nil, ConvexConfig.isConfigured else {
            state = .localOnly
            return
        }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            let seconds = self?.pushDebounceSeconds ?? 5.0
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.pushLocalChanges()
        }
    }

    func forceSync() async {
        guard apiKey != nil else { return }
        pushTask?.cancel()
        await pushLocalChanges()
        if propertiesSubscription == nil || billsSubscription == nil {
            startRealtimeSubscriptions()
        }
    }

    // MARK: - Push (batched)
    private func pushLocalChanges() async {
        guard let context = modelContext,
              let client = client,
              let apiKey = apiKey else { return }
        guard !Task.isCancelled else { return }

        await MainActor.run { self.state = .syncing }

        let billsToPush: [Bill]
        let propsToPush: [Property]
        do {
            billsToPush = try context.fetch(
                FetchDescriptor<Bill>(predicate: #Predicate { $0.syncStatusRaw != "synced" })
            )
            propsToPush = try context.fetch(
                FetchDescriptor<Property>(predicate: #Predicate { $0.syncStatusRaw != "synced" })
            )
        } catch {
            print("❌ [Sync] Fetch failed: \(error)")
            await MainActor.run { self.state = .error("Fetch failed") }
            return
        }

        let billDeletes = Array(pendingBillDeletes)
        let propDeletes = Array(pendingPropertyDeletes)
        let totalPending = propsToPush.count + billsToPush.count + billDeletes.count + propDeletes.count

        if totalPending == 0 {
            await MainActor.run {
                self.pendingCount = 0
                self.state = self.isLive ? .live : .idle
            }
            return
        }

        await MainActor.run { self.pendingCount = totalPending }

        var failures: [String] = []

        // 1. Properties — one mutation.
        if !propsToPush.isEmpty {
            do {
                try await batchUpsertProperties(propsToPush, client: client, apiKey: apiKey)
                for prop in propsToPush { prop.syncStatus = .synced }
                try? context.save()
                print("✅ [Sync] Batch pushed \(propsToPush.count) properties")
            } catch {
                failures.append("Properties: \(error.localizedDescription)")
                print("❌ [Sync] Property batch failed: \(error)")
            }
        }

        // 2. Bills — one mutation, only for bills whose property is synced.
        if !billsToPush.isEmpty {
            let ready = billsToPush.filter { bill in
                guard let prop = bill.property else { return false }
                return prop.syncStatus == .synced
            }
            let deferred = billsToPush.count - ready.count
            if deferred > 0 {
                print("⏳ [Sync] Deferring \(deferred) bills until their properties are synced")
            }

            if !ready.isEmpty {
                do {
                    try await batchUpsertBills(ready, client: client, apiKey: apiKey)
                    for bill in ready { bill.syncStatus = .synced }
                    try? context.save()
                    print("✅ [Sync] Batch pushed \(ready.count) bills")
                } catch {
                    failures.append("Bills: \(error.localizedDescription)")
                    print("❌ [Sync] Bill batch failed: \(error)")
                }
            }

            if deferred > 0 {
                schedulePush()
            }
        }

        // 3. Delete bills — one mutation.
        if !billDeletes.isEmpty {
            do {
                try await batchDeleteBills(billDeletes, client: client, apiKey: apiKey)
                pendingBillDeletes.subtract(billDeletes)
                print("✅ [Sync] Batch deleted \(billDeletes.count) bills")
            } catch {
                failures.append("Bill deletes: \(error.localizedDescription)")
                print("❌ [Sync] Bill batch delete failed: \(error)")
            }
        }

        // 4. Delete properties — one mutation.
        if !propDeletes.isEmpty {
            do {
                try await batchDeleteProperties(propDeletes, client: client, apiKey: apiKey)
                pendingPropertyDeletes.subtract(propDeletes)
                print("✅ [Sync] Batch deleted \(propDeletes.count) properties")
            } catch {
                failures.append("Property deletes: \(error.localizedDescription)")
                print("❌ [Sync] Property batch delete failed: \(error)")
            }
        }

        await MainActor.run {
            self.pendingCount = (billsToPush.count + propsToPush.count + billDeletes.count + propDeletes.count)
            self.lastSyncAt = Date()
            self.lastError = failures.first

            if failures.isEmpty {
                self.state = self.isLive ? .live : .idle
                self.retryAttempt = 0
            } else {
                self.state = .error(failures.first ?? "Sync failed")
                self.scheduleRetry()
            }
        }
    }

    // MARK: - Batch network calls (JSON-encoded)
    private func batchUpsertProperties(
        _ properties: [Property],
        client: ConvexClient,
        apiKey: String
    ) async throws {
        let items: [[String: Any]] = properties.map { prop in
            var dict: [String: Any] = [
                "externalId": prop.id,
                "name": prop.name,
                "colorHex": prop.colorHex,
                "monthlyBudget": prop.monthlyBudget,
                "isDefault": prop.isDefault,
                "updatedAt": prop.updatedAt.timeIntervalSince1970 * 1000,
            ]
            if let address = prop.address, !address.isEmpty {
                dict["address"] = address
            }
            return dict
        }

        let json = Self.encodeJSON(items)
        let payload: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
            "itemsJson": json,
        ]
        let _: BatchMutationResponse = try await client.mutation(
            "rentaman:batchUpsertProperties",
            with: payload
        )
    }

    private func batchUpsertBills(
        _ bills: [Bill],
        client: ConvexClient,
        apiKey: String
    ) async throws {
        let items: [[String: Any]] = bills.compactMap { bill -> [String: Any]? in
            guard let propertyId = bill.property?.id, !propertyId.isEmpty else { return nil }
            var dict: [String: Any] = [
                "externalId": bill.id,
                "title": bill.title,
                "amount": bill.amount,
                "categoryRawValue": bill.categoryRawValue,
                "dueDate": bill.dueDate.timeIntervalSince1970 * 1000,
                "isPaid": bill.isPaid,
                "isRecurring": bill.isRecurring,
                "recurringFrequencyRaw": bill.recurringFrequencyRaw,
                "propertyExternalId": propertyId,
                "updatedAt": bill.updatedAt.timeIntervalSince1970 * 1000,
            ]
            if let paymentDate = bill.paymentDate {
                dict["paymentDate"] = paymentDate.timeIntervalSince1970 * 1000
            }
            if let notes = bill.notes, !notes.isEmpty {
                dict["notes"] = notes
            }
            if let receiptId = bill.receiptIdentifier, !receiptId.isEmpty {
                dict["receiptIdentifier"] = receiptId
            }
            return dict
        }

        guard !items.isEmpty else { return }

        let json = Self.encodeJSON(items)
        let payload: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
            "itemsJson": json,
        ]
        let _: BatchMutationResponse = try await client.mutation(
            "rentaman:batchUpsertBills",
            with: payload
        )
    }

    private func batchDeleteBills(
        _ ids: [String],
        client: ConvexClient,
        apiKey: String
    ) async throws {
        let payload: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
            "externalIdsJson": Self.encodeJSON(ids),
            "updatedAt": Date().timeIntervalSince1970 * 1000,
        ]
        let _: BatchMutationResponse = try await client.mutation(
            "rentaman:batchDeleteBills",
            with: payload
        )
    }

    private func batchDeleteProperties(
        _ ids: [String],
        client: ConvexClient,
        apiKey: String
    ) async throws {
        let payload: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
            "externalIdsJson": Self.encodeJSON(ids),
            "updatedAt": Date().timeIntervalSince1970 * 1000,
        ]
        let _: BatchMutationResponse = try await client.mutation(
            "rentaman:batchDeleteProperties",
            with: payload
        )
    }

    private static func encodeJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    // MARK: - Local upserts (from incoming stream)
    @discardableResult
    private func upsertLocalProperty(_ remote: RemoteProperty, context: ModelContext) -> Property {
        let remoteId = remote.externalId
        let remoteDate = Date(timeIntervalSince1970: remote.updatedAt / 1000)

        if let existing = findProperty(id: remoteId, context: context) {
            if existing.syncStatus != .synced && existing.updatedAt > remoteDate {
                return existing
            }
            if remoteDate.timeIntervalSince(existing.updatedAt) > 0.001 {
                existing.name = remote.name
                existing.address = remote.address
                existing.colorHex = remote.colorHex
                existing.monthlyBudget = remote.monthlyBudget
                existing.isDefault = remote.isDefault
                existing.updatedAt = remoteDate
                existing.syncStatus = .synced
            }
            return existing
        }

        let newProp = Property(
            id: remote.externalId,
            name: remote.name,
            address: remote.address,
            colorHex: remote.colorHex,
            monthlyBudget: remote.monthlyBudget,
            isDefault: remote.isDefault
        )
        newProp.updatedAt = remoteDate
        newProp.syncStatus = .synced
        context.insert(newProp)
        return newProp
    }

    private func upsertLocalBill(_ remote: RemoteBill, context: ModelContext) {
        let remoteId = remote.externalId
        let remotePropertyId = remote.propertyExternalId
        let remoteDate = Date(timeIntervalSince1970: remote.updatedAt / 1000)

        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { $0.id == remoteId })
        let existing = try? context.fetch(descriptor).first

        if let existing = existing {
            if existing.syncStatus != .synced && existing.updatedAt > remoteDate { return }

            if existing.property == nil {
                if let prop = findProperty(id: remotePropertyId, context: context) {
                    existing.property = prop
                } else {
                    orphanBills.append(remote)
                    return
                }
            }

            guard remoteDate.timeIntervalSince(existing.updatedAt) > 0.001 else { return }

            existing.title = remote.title
            existing.amount = remote.amount
            existing.categoryRawValue = remote.categoryRawValue
            existing.dueDate = Date(timeIntervalSince1970: remote.dueDate / 1000)
            existing.isPaid = remote.isPaid
            existing.paymentDate = remote.paymentDate.map { Date(timeIntervalSince1970: $0 / 1000) }
            existing.notes = remote.notes
            existing.isRecurring = remote.isRecurring
            existing.recurringFrequencyRaw = remote.recurringFrequencyRaw
            existing.updatedAt = remoteDate
            existing.syncStatus = .synced
        } else {
            guard let property = findProperty(id: remotePropertyId, context: context) else {
                orphanBills.append(remote)
                return
            }

            let newBill = Bill(
                id: remote.externalId,
                title: remote.title,
                amount: remote.amount,
                category: ExpenseCategory(rawValue: remote.categoryRawValue) ?? .miscellaneous,
                dueDate: Date(timeIntervalSince1970: remote.dueDate / 1000),
                isPaid: remote.isPaid,
                property: property,
                isRecurring: remote.isRecurring,
                recurringFrequency: RecurringFrequency(rawValue: remote.recurringFrequencyRaw) ?? .none
            )
            newBill.notes = remote.notes
            newBill.paymentDate = remote.paymentDate.map { Date(timeIntervalSince1970: $0 / 1000) }
            newBill.updatedAt = remoteDate
            newBill.syncStatus = .synced
            context.insert(newBill)
        }
    }

    private func findProperty(id: String, context: ModelContext) -> Property? {
        let descriptor = FetchDescriptor<Property>()
        guard let all = try? context.fetch(descriptor) else { return nil }
        return all.first(where: { $0.id == id })
    }

    // MARK: - Deletes (queued → batched)
    func deleteBill(_ bill: Bill) async {
        await MainActor.run {
            if let context = modelContext {
                let id = bill.id
                context.delete(bill)
                try? context.save()
                pendingBillDeletes.insert(id)
            }
        }
        schedulePush()
    }

    func deleteProperty(_ property: Property) async {
        await MainActor.run {
            if let context = modelContext {
                let id = property.id
                for bill in property.bills {
                    pendingBillDeletes.insert(bill.id)
                }
                context.delete(property)
                try? context.save()
                pendingPropertyDeletes.insert(id)
            }
        }
        schedulePush()
    }

    // MARK: - Retry
    private func scheduleRetry() {
        retryAttempt += 1
        let delay = min(
            ConvexConfig.retryBaseSeconds * pow(2, Double(retryAttempt - 1)),
            ConvexConfig.retryMaxSeconds
        )
        print("⏳ [Sync] Retrying in \(Int(delay))s (attempt \(retryAttempt))")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.pushLocalChanges()
        }
    }
}

// MARK: - DTOs
struct RemoteProperty: Decodable, Hashable {
    let externalId: String
    let name: String
    let address: String?
    let colorHex: String
    let monthlyBudget: Double
    let isDefault: Bool
    let updatedAt: Double
}

struct RemoteBill: Decodable, Hashable {
    let externalId: String
    let title: String
    let amount: Double
    let categoryRawValue: String
    let dueDate: Double
    let isPaid: Bool
    let paymentDate: Double?
    let notes: String?
    let receiptIdentifier: String?
    let isRecurring: Bool
    let recurringFrequencyRaw: String
    let propertyExternalId: String
    let updatedAt: Double
}