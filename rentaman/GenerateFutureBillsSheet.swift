import SwiftUI
import SwiftData

// MARK: - Generator
struct FutureBillsGenerator {

    // MARK: Template
    struct Template: Identifiable {
        let id: String
        let title: String
        let amount: Double
        let category: ExpenseCategory
        let property: Property?
        let frequency: RecurringFrequency
        let lastDueDate: Date
        let instanceCount: Int
        let isPaused: Bool     // 🆕

        var effectiveFrequency: RecurringFrequency {
            frequency == .none ? .monthly : frequency
        }
    }

    // MARK: Result
    struct GenerationResult {
        let created: Int
        let skipped: Int
        let createdTitles: [String]
        let skippedTitles: [String]
        let firstDate: Date?
        let lastDate: Date?
    }

    // MARK: Build templates from existing bills
    static func templates(from bills: [Bill]) -> [Template] {
        let recurring = bills.filter { $0.isRecurring }

        var grouped: [String: [Bill]] = [:]
        for bill in recurring {
            let key = "\(bill.title.lowercased())|\(bill.property?.id ?? "none")"
            grouped[key, default: []].append(bill)
        }

        return grouped.compactMap { key, group -> Template? in
            guard let newest = group.max(by: { $0.dueDate < $1.dueDate }) else { return nil }
            return Template(
                id: key,
                title: newest.title,
                amount: newest.amount,
                category: newest.category,
                property: newest.property,
                frequency: newest.recurringFrequency,
                lastDueDate: newest.dueDate,
                instanceCount: group.count,
                isPaused: newest.isPaused
            )
        }
        .sorted { lhs, rhs in
            // Active templates before paused ones
            if lhs.isPaused != rhs.isPaused {
                return !lhs.isPaused
            }
            if lhs.title.lowercased() == rhs.title.lowercased() {
                return (lhs.property?.name ?? "") < (rhs.property?.name ?? "")
            }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
    }

    // MARK: - Canonical cycle day
    static func anchorDay(for template: Template) -> Int {
        let rawDay = Calendar.current.component(.day, from: template.lastDueDate)
        return rawDay <= 1 ? 5 : rawDay
    }

    // MARK: - Generate
    @MainActor
    @discardableResult
    static func generate(
        templates: [Template],
        periodsForward: Int,
        context: ModelContext
    ) -> GenerationResult {
        // 🆕 Exclude paused templates defensively.
        let activeTemplates = templates.filter { !$0.isPaused }

        guard !activeTemplates.isEmpty, periodsForward > 0 else {
            return GenerationResult(
                created: 0, skipped: 0,
                createdTitles: [], skippedTitles: [],
                firstDate: nil, lastDate: nil
            )
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        let allDescriptor = FetchDescriptor<Bill>()
        let allBills = (try? context.fetch(allDescriptor)) ?? []
        var existingKeys = Set<String>()
        for bill in allBills {
            existingKeys.insert(key(for: bill.title,
                                    propertyId: bill.property?.id,
                                    date: bill.dueDate,
                                    calendar: calendar))
        }

        var created = 0
        var skipped = 0
        var createdTitles: [String] = []
        var skippedTitles: [String] = []
        var firstDate: Date? = nil
        var lastDate: Date? = nil

        for template in activeTemplates {
            let freq = template.effectiveFrequency
            let targetDay = anchorDay(for: template)

            guard var cursor = nextFutureCycle(
                template: template,
                freq: freq,
                anchorDay: targetDay,
                calendar: calendar,
                today: startOfToday
            ) else { continue }

            var createdForThisTemplate = 0

            while createdForThisTemplate < periodsForward {
                if calendar.startOfDay(for: cursor) <= startOfToday {
                    guard let next = advance(cursor, by: freq, calendar: calendar) else { break }
                    cursor = reanchor(next, toDay: targetDay, calendar: calendar) ?? next
                    continue
                }

                let k = key(for: template.title,
                            propertyId: template.property?.id,
                            date: cursor,
                            calendar: calendar)

                if existingKeys.contains(k) {
                    skipped += 1
                    skippedTitles.append(template.title)
                } else {
                    let newBill = Bill(
                        title: template.title,
                        amount: template.amount,
                        category: template.category,
                        dueDate: cursor,
                        isPaid: false,
                        property: template.property,
                        isRecurring: true,
                        recurringFrequency: freq
                    )
                    newBill.syncStatus = .pendingUpload
                    newBill.updatedAt = Date()
                    context.insert(newBill)
                    existingKeys.insert(k)
                    created += 1
                    createdTitles.append(template.title)

                    if firstDate == nil || cursor < firstDate! { firstDate = cursor }
                    if lastDate == nil  || cursor > lastDate!  { lastDate  = cursor }
                }

                createdForThisTemplate += 1

                guard let next = advance(cursor, by: freq, calendar: calendar) else { break }
                cursor = reanchor(next, toDay: targetDay, calendar: calendar) ?? next
            }
        }

        if created > 0 {
            try? context.save()
            SyncService.shared.schedulePush()
        }

        return GenerationResult(
            created: created,
            skipped: skipped,
            createdTitles: createdTitles,
            skippedTitles: skippedTitles,
            firstDate: firstDate,
            lastDate: lastDate
        )
    }

    // MARK: - Next future cycle
    private static func nextFutureCycle(
        template: Template,
        freq: RecurringFrequency,
        anchorDay: Int,
        calendar: Calendar,
        today: Date
    ) -> Date? {
        if freq == .weekly {
            var probe = template.lastDueDate
            var safety = 0
            while safety < 500 {
                safety += 1
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: probe) else { break }
                probe = next
                if calendar.startOfDay(for: probe) > today { return probe }
            }
            return nil
        }

        let todayY = calendar.component(.year, from: today)
        let todayM = calendar.component(.month, from: today)

        let stepMonths: Int
        switch freq {
        case .quarterly: stepMonths = 3
        case .yearly:    stepMonths = 12
        default:         stepMonths = 1
        }

        var probeY = todayY
        var probeM = todayM
        var safety = 0

        while safety < 240 {
            safety += 1
            guard let candidate = calendar.date(from: DateComponents(
                year: probeY, month: probeM, day: anchorDay, hour: 12
            )) else { break }

            if calendar.startOfDay(for: candidate) > today {
                return candidate
            }

            probeM += stepMonths
            while probeM > 12 { probeM -= 12; probeY += 1 }
        }
        return nil
    }

    // MARK: - Preview
    static func previewFirstDate(
        templates: [Template],
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: Date())
        var earliest: Date? = nil
        for template in templates where !template.isPaused {
            let freq = template.effectiveFrequency
            let day = anchorDay(for: template)
            if let d = nextFutureCycle(
                template: template, freq: freq,
                anchorDay: day, calendar: calendar, today: today
            ) {
                if earliest == nil || d < earliest! { earliest = d }
            }
        }
        return earliest
    }

    // MARK: - Helpers
    private static func key(
        for title: String,
        propertyId: String?,
        date: Date,
        calendar: Calendar
    ) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        return "\(title.lowercased())|\(y)|\(m)|\(propertyId ?? "none")"
    }

    private static func advance(
        _ date: Date,
        by freq: RecurringFrequency,
        calendar: Calendar
    ) -> Date? {
        switch freq {
        case .none:      return nil
        case .weekly:    return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:   return calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date)
        case .yearly:    return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }

    private static func reanchor(
        _ date: Date,
        toDay day: Int,
        calendar: Calendar
    ) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(
            year: comps.year, month: comps.month, day: day, hour: 12
        ))
    }
}

// MARK: - Sheet
struct GenerateFutureBillsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrency) private var currency: AppCurrency
   @Query(filter: #Predicate<Bill> { $0.isDeleted == false })
private var allBills: [Bill]

    @State private var periodsForward: Int = 6
    @State private var selectedIds: Set<String> = []
    @State private var result: FutureBillsGenerator.GenerationResult? = nil

    private var templates: [FutureBillsGenerator.Template] {
        FutureBillsGenerator.templates(from: allBills)
    }

    private var activeTemplates: [FutureBillsGenerator.Template] {
        templates.filter { !$0.isPaused }
    }

    private var pausedTemplates: [FutureBillsGenerator.Template] {
        templates.filter { $0.isPaused }
    }

    private var selectedTemplates: [FutureBillsGenerator.Template] {
        activeTemplates.filter { selectedIds.contains($0.id) }
    }

    private var projectedNewCount: Int {
        guard periodsForward > 0 else { return 0 }
        return selectedTemplates.count * periodsForward
    }

    private var projectedCost: Double {
        selectedTemplates.reduce(0.0) { $0 + $1.amount } * Double(periodsForward)
    }

    private var previewFirstDate: Date? {
        FutureBillsGenerator.previewFirstDate(templates: selectedTemplates)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if templates.isEmpty {
                emptyState
            } else if let result {
                resultView(result)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        periodPicker
                        summaryCard
                        listHeader
                        templatesList
                    }
                    .padding(20)
                }
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 680)
        .onAppear {
            selectedIds = Set(activeTemplates.map { $0.id })
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generate Future Bills")
                    .font(.title2).fontWeight(.bold)
                Text("Pre-create your recurring bills from the next cycle onward")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    // MARK: - Period picker
    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How many future cycles?")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                ForEach([3, 6, 12], id: \.self) { m in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            periodsForward = m
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(m)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("cycles")
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(periodsForward == m ? .white : .primary)
                        .background {
                            if periodsForward == m {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.gradient)
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.08))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Each bill is anchored to its normal day-of-month — cycles already in the past are skipped automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Summary
    private var summaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Will create")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text("\(projectedNewCount) bills")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("Total value")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(CurrencyFormatter.format(projectedCost, as: currency))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("First cycle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(previewFirstDate.map { $0.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) } ?? "—")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.purple)
            }
            Spacer()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color.green.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - List header
    private var listHeader: some View {
        HStack {
            Text("Recurring bills detected")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(selectedIds.count == activeTemplates.count ? "Deselect all" : "Select all") {
                if selectedIds.count == activeTemplates.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(activeTemplates.map { $0.id })
                }
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .disabled(activeTemplates.isEmpty)
        }
    }

    // MARK: - List
    private var templatesList: some View {
        VStack(spacing: 6) {
            ForEach(activeTemplates) { template in
                templateRow(template, enabled: true)
            }

            if !pausedTemplates.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Paused")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pausedTemplates.count) skipped")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 10)
                .padding(.horizontal, 4)

                ForEach(pausedTemplates) { template in
                    templateRow(template, enabled: false)
                }
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: FutureBillsGenerator.Template, enabled: Bool) -> some View {
        let isSelected = selectedIds.contains(template.id)
        let day = FutureBillsGenerator.anchorDay(for: template)

        Button {
            guard enabled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                if isSelected {
                    selectedIds.remove(template.id)
                } else {
                    selectedIds.insert(template.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: enabled
                      ? (isSelected ? "checkmark.circle.fill" : "circle")
                      : "pause.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(enabled
                                     ? (isSelected ? .blue : .secondary)
                                     : .orange)

                Image(systemName: template.category.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(template.category.color)
                    .frame(width: 28, height: 28)
                    .background(template.category.color.opacity(0.12))
                    .cornerRadius(7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if template.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.gradient)
                                .cornerRadius(3)
                        }
                    }
                    HStack(spacing: 6) {
                        if let prop = template.property {
                            Text(prop.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Text("day \(day)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(template.effectiveFrequency.rawValue)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text("last \(template.lastDueDate.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(CurrencyFormatter.format(template.amount, as: currency))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .background(enabled
                        ? (isSelected ? Color.blue.opacity(0.04) : Color(NSColor.controlBackgroundColor))
                        : Color.orange.opacity(0.04))
            .cornerRadius(9)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        enabled
                            ? (isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.1))
                            : Color.orange.opacity(0.25),
                        lineWidth: enabled ? (isSelected ? 1.2 : 1) : 1
                    )
            )
            .opacity(enabled ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Result
    private func resultView(_ result: FutureBillsGenerator.GenerationResult) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green.gradient)

            VStack(spacing: 6) {
                Text("Generated \(result.created) new bill\(result.created == 1 ? "" : "s")")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                if let first = result.firstDate, let last = result.lastDate {
                    Text("From \(first.formatted(.dateTime.day().month(.abbreviated).year())) to \(last.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if result.skipped > 0 {
                    Text("Skipped \(result.skipped) already existing")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if !result.createdTitles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(uniqueTitles(result.createdTitles).prefix(8)), id: \.self) { t in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text(t)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if uniqueTitles(result.createdTitles).count > 8 {
                        Text("+ \(uniqueTitles(result.createdTitles).count - 8) more…")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(14)
                .background(Color.green.opacity(0.06))
                .cornerRadius(10)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private func uniqueTitles(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in titles {
            if !seen.contains(t.lowercased()) {
                seen.insert(t.lowercased())
                out.append(t)
            }
        }
        return out
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No recurring bills found")
                .font(.system(size: 14, weight: .semibold))
            Text("Mark a bill as recurring when you add or edit it, and it will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Footer
    private var footer: some View {
        HStack {
            if result != nil {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    runGeneration()
                } label: {
                    Label("Generate \(projectedNewCount) Bill\(projectedNewCount == 1 ? "" : "s")",
                          systemImage: "calendar.badge.plus")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedTemplates.isEmpty || periodsForward <= 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    // MARK: - Run
    private func runGeneration() {
        let r = FutureBillsGenerator.generate(
            templates: selectedTemplates,
            periodsForward: periodsForward,
            context: modelContext
        )
        withAnimation(.easeOut(duration: 0.25)) {
            result = r
        }
    }
}