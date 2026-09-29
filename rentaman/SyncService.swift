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
    case live            // 🆕 connected to live stream
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

// MARK: - Convex Mutation Response
struct ConvexMutationResponse: Decodable {
    let status: String?
    let reason: String?
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
    
    var state: SyncState = .localOnly
    var lastSyncAt: Date? = nil
    var pendingCount: Int = 0
    var lastError: String? = nil
    var isLive: Bool = false
    
    private var modelContext: ModelContext?
    private var pushTask: Task<Void, Never>?
    private var retryAttempt: Int = 0
    private var client: ConvexClient?
    private var apiKey: String?
    
    // 🆕 Real-time subscription handles
    private var propertiesSubscription: AnyCancellable?
    private var billsSubscription: AnyCancellable?
    
    static let shared = SyncService()
    private init() {}
    
    // MARK: - Setup
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        if !ConvexConfig.isConfigured {
            state = .localOnly
        }
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
        
        // 🆕 Start live subscriptions instead of just pulling once
        startRealtimeSubscriptions()
        
        // Also do an initial push in case there are pending local changes
        Task { await pushLocalChanges() }
    }
    
    func reset() {
        // 🆕 Cancel live subscriptions on sign out
        stopRealtimeSubscriptions()
        
        apiKey = nil
        state = .localOnly
        pendingCount = 0
        lastSyncAt = nil
        lastError = nil
        isLive = false
        pushTask?.cancel()
        pushTask = nil
    }
    
    // MARK: - Real-time Subscriptions
    private func startRealtimeSubscriptions() {
        guard let client = client, let apiKey = apiKey else { return }
        
        // Cancel any existing subscriptions first
        stopRealtimeSubscriptions()
        
        print("📡 [Sync] Starting real-time subscriptions…")
        
        let propsArgs: [String: ConvexEncodable?] = ["apiKey": apiKey]
        let propsPublisher = client.subscribe(
            to: "rentaman:listProperties",
            with: propsArgs,
            yielding: [RemoteProperty].self
        )
        
        propertiesSubscription = propsPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    switch completion {
                    case .finished:
                        print("📡 [Sync] Properties subscription finished")
                    case .failure(let error):
                        print("❌ [Sync] Properties subscription failed: \(error)")
                        self.isLive = false
                        self.state = .error("Live properties stream failed: \(error.localizedDescription)")
                        // Retry after a delay
                        self.scheduleSubscriptionRetry()
                    }
                },
                receiveValue: { [weak self] remoteProps in
                    guard let self = self, let context = self.modelContext else { return }
                    print("📡 [Sync] Received \(remoteProps.count) properties from live stream")
                    for remote in remoteProps {
                        self.upsertLocalProperty(remote, context: context)
                    }
                    try? context.save()
                    self.lastSyncAt = Date()
                    self.markLiveIfReady()
                }
            )
        
        let billsArgs: [String: ConvexEncodable?] = ["apiKey": apiKey]
        let billsPublisher = client.subscribe(
            to: "rentaman:listBills",
            with: billsArgs,
            yielding: [RemoteBill].self
        )
        
        billsSubscription = billsPublisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    switch completion {
                    case .finished:
                        print("📡 [Sync] Bills subscription finished")
                    case .failure(let error):
                        print("❌ [Sync] Bills subscription failed: \(error)")
                        self.isLive = false
                        self.state = .error("Live bills stream failed: \(error.localizedDescription)")
                        self.scheduleSubscriptionRetry()
                    }
                },
                receiveValue: { [weak self] remoteBills in
                    guard let self = self, let context = self.modelContext else { return }
                    print("📡 [Sync] Received \(remoteBills.count) bills from live stream")
                    for remote in remoteBills {
                        self.upsertLocalBill(remote, context: context)
                    }
                    try? context.save()
                    self.lastSyncAt = Date()
                    self.markLiveIfReady()
                }
            )
    }
    
    private func stopRealtimeSubscriptions() {
        propertiesSubscription?.cancel()
        billsSubscription?.cancel()
        propertiesSubscription = nil
        billsSubscription = nil
        isLive = false
    }
    
    private func markLiveIfReady() {
        // Mark as live once both streams have delivered at least one payload
        if propertiesSubscription != nil && billsSubscription != nil && !isLive {
            isLive = true
            // Only override state if we're not currently pushing
            if state != .syncing {
                state = .live
            }
        }
    }
    
    private func scheduleSubscriptionRetry() {
        print("⏳ [Sync] Retrying subscriptions in 10s")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self = self, self.apiKey != nil else { return }
            self.startRealtimeSubscriptions()
        }
    }
    
    // MARK: - Manual Triggers
    func schedulePush() {
        guard apiKey != nil, ConvexConfig.isConfigured else {
            state = .localOnly
            return
        }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ConvexConfig.pushDebounceSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.pushLocalChanges()
        }
    }
    
    func forceSync() async {
        guard apiKey != nil else { return }
        await pushLocalChanges()
        // Restart subscriptions in case they were dropped
        startRealtimeSubscriptions()
    }
    
    // MARK: - Push (Local → Convex)
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
            print("❌ [Sync] fetch failed: \(error)")
            await MainActor.run {
                self.state = .error("Fetch failed: \(error.localizedDescription)")
            }
            return
        }
        
        if propsToPush.isEmpty && billsToPush.isEmpty {
            // Nothing to push — make sure state reflects live if we have a subscription
            if isLive {
                await MainActor.run { self.state = .live }
            } else {
                await MainActor.run { self.state = .idle }
            }
            return
        }
        
        print("🔄 [Sync] Pushing \(propsToPush.count) properties, \(billsToPush.count) bills")
        
        await MainActor.run {
            self.pendingCount = billsToPush.count + propsToPush.count
        }
        
        var failureCount = 0
        var lastErrorMsg: String? = nil
        
        for property in propsToPush {
            if Task.isCancelled { return }
            do {
                try await pushProperty(property, client: client, apiKey: apiKey)
                property.syncStatus = .synced
                print("✅ [Sync] Pushed property: \(property.name)")
            } catch {
                failureCount += 1
                lastErrorMsg = "Property '\(property.name)': \(error.localizedDescription)"
                print("❌ [Sync] Failed to push property '\(property.name)': \(error)")
            }
        }
        
        for bill in billsToPush {
            if Task.isCancelled { return }
            do {
                try await pushBill(bill, client: client, apiKey: apiKey)
                bill.syncStatus = .synced
                print("✅ [Sync] Pushed bill: \(bill.title) (\(bill.amount))")
            } catch {
                failureCount += 1
                lastErrorMsg = "Bill '\(bill.title)': \(error.localizedDescription)"
                print("❌ [Sync] Failed to push bill '\(bill.title)': \(error)")
            }
        }
        
        do {
            try context.save()
        } catch {
            print("⚠️ [Sync] context.save failed: \(error)")
        }
        
        await MainActor.run {
            self.pendingCount = failureCount
            self.lastSyncAt = Date()
            self.lastError = lastErrorMsg
            
            if failureCount == 0 {
                self.state = self.isLive ? .live : .idle
                self.retryAttempt = 0
            } else {
                self.state = .error(lastErrorMsg ?? "Some items failed to sync")
                self.scheduleRetry()
            }
        }
    }
    
    // MARK: - Push Property
    private func pushProperty(_ property: Property, client: ConvexClient, apiKey: String) async throws {
        var payload: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
            "externalId": property.id,
            "name": property.name,
            "colorHex": property.colorHex,
            "monthlyBudget": property.monthlyBudget,
            "isDefault": property.isDefault,
            "updatedAt": property.updatedAt.timeIntervalSince1970 * 1000,
        ]
        if let address = property.address, !address.isEmpty {
            payload["address"] = address
        }
        
        let _: ConvexMutationResponse = try await client.mutation(
            "rentaman:upsertProperty",
            with: payload
        )
    }
    
    // MARK: - Push Bill
    private func pushBill(_ bill: Bill, client: ConvexClient, apiKey: String) async throws {
        guard let propertyId = bill.property?.id, !propertyId.isEmpty else {
            throw NSError(
                domain: "RentaMan.Sync",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Bill has no property linked"]
            )
        }
        
        var payload: [String: ConvexEncodable?] = [
            "apiKey": apiKey,
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
            payload["paymentDate"] = paymentDate.timeIntervalSince1970 * 1000
        }
        if let notes = bill.notes, !notes.isEmpty {
            payload["notes"] = notes
        }
        if let receiptId = bill.receiptIdentifier, !receiptId.isEmpty {
            payload["receiptIdentifier"] = receiptId
        }
        
        let _: ConvexMutationResponse = try await client.mutation(
            "rentaman:upsertBill",
            with: payload
        )
    }
    
    // MARK: - Delete Operations (server-first)
    func deleteBill(_ bill: Bill) async {
        if let client = client, let apiKey = apiKey {
            let payload: [String: ConvexEncodable?] = [
                "apiKey": apiKey,
                "externalId": bill.id,
                "updatedAt": Date().timeIntervalSince1970 * 1000,
            ]
            do {
                let _: ConvexMutationResponse = try await client.mutation(
                    "rentaman:deleteBill",
                    with: payload
                )
                print("✅ [Sync] Deleted bill on server: \(bill.title)")
            } catch {
                print("⚠️ [Sync] Server delete failed for '\(bill.title)': \(error). Proceeding with local delete.")
            }
        }
        
        await MainActor.run {
            if let context = modelContext {
                context.delete(bill)
                try? context.save()
            }
        }
    }
    
    func deleteProperty(_ property: Property) async {
        if let client = client, let apiKey = apiKey {
            let payload: [String: ConvexEncodable?] = [
                "apiKey": apiKey,
                "externalId": property.id,
                "updatedAt": Date().timeIntervalSince1970 * 1000,
            ]
            do {
                let _: ConvexMutationResponse = try await client.mutation(
                    "rentaman:deleteProperty",
                    with: payload
                )
                print("✅ [Sync] Deleted property on server: \(property.name)")
            } catch {
                print("⚠️ [Sync] Server delete failed for '\(property.name)': \(error). Proceeding with local delete.")
            }
        }
        
        await MainActor.run {
            if let context = modelContext {
                context.delete(property)
                try? context.save()
            }
        }
    }
    
    // MARK: - Local Upserts (from live stream)
    private func upsertLocalProperty(_ remote: RemoteProperty, context: ModelContext) {
        let remoteId = remote.externalId
        let descriptor = FetchDescriptor<Property>(predicate: #Predicate { $0.id == remoteId })
        let existing = try? context.fetch(descriptor).first
        let remoteDate = Date(timeIntervalSince1970: remote.updatedAt / 1000)
        
        if let existing = existing {
            // Skip if local change is newer or pending
            if existing.syncStatus != .synced && existing.updatedAt > remoteDate {
                return
            }
            if remoteDate > existing.updatedAt {
                existing.name = remote.name
                existing.address = remote.address
                existing.colorHex = remote.colorHex
                existing.monthlyBudget = remote.monthlyBudget
                existing.isDefault = remote.isDefault
                existing.updatedAt = remoteDate
                existing.syncStatus = .synced
            }
        } else {
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
        }
    }
    
    private func upsertLocalBill(_ remote: RemoteBill, context: ModelContext) {
        let remoteId = remote.externalId
        let remotePropertyId = remote.propertyExternalId
        
        let descriptor = FetchDescriptor<Bill>(predicate: #Predicate { $0.id == remoteId })
        let existing = try? context.fetch(descriptor).first
        let remoteDate = Date(timeIntervalSince1970: remote.updatedAt / 1000)
        
        if let existing = existing {
            if existing.syncStatus != .synced && existing.updatedAt > remoteDate {
                return
            }
            if remoteDate > existing.updatedAt {
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
            }
        } else {
            let newBill = Bill(
                id: remote.externalId,
                title: remote.title,
                amount: remote.amount,
                category: ExpenseCategory(rawValue: remote.categoryRawValue) ?? .miscellaneous,
                dueDate: Date(timeIntervalSince1970: remote.dueDate / 1000),
                isPaid: remote.isPaid,
                property: nil,
                isRecurring: remote.isRecurring,
                recurringFrequency: RecurringFrequency(rawValue: remote.recurringFrequencyRaw) ?? .none
            )
            newBill.notes = remote.notes
            newBill.paymentDate = remote.paymentDate.map { Date(timeIntervalSince1970: $0 / 1000) }
            newBill.updatedAt = remoteDate
            newBill.syncStatus = .synced
            
            let propDescriptor = FetchDescriptor<Property>(predicate: #Predicate { $0.id == remotePropertyId })
            newBill.property = try? context.fetch(propDescriptor).first
            
            context.insert(newBill)
        }
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

// MARK: - Remote DTOs
struct RemoteProperty: Decodable {
    let externalId: String
    let name: String
    let address: String?
    let colorHex: String
    let monthlyBudget: Double
    let isDefault: Bool
    let updatedAt: Double
}

struct RemoteBill: Decodable {
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