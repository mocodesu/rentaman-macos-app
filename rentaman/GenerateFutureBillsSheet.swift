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
        let isPaused: Bool

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
            Divider().opacity(0.5)

            if templates.isEmpty {
                emptyState
            } else if let result {
                resultView(result)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        periodPicker
                        summaryCard
                        listHeader
                        templatesList
                    }
                    .padding(16)
                }
            }

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 640, height: 680)
        .background(RMDesign.pageBackground)
        .onAppear {
            selectedIds = Set(activeTemplates.map { $0.id })
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(RMDesign.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Generate Future Bills")
                    .font(.system(size: 16, weight: .semibold))
                Text("Pre-create your recurring bills from the next cycle onward")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    // MARK: - Period picker
    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How many future cycles?")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 6) {
                ForEach([3, 6, 12], id: \.self) { m in
                    Button {
                        withAnimation(RMDesign.ease) {
                            periodsForward = m
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(m)")
                                .font(.system(size: 16, weight: .semibold))
                                .monospacedDigit()
                            Text("cycles")
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(periodsForward == m ? .white : .primary)
                        .background {
                            if periodsForward == m {
                                RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                                    .fill(RMDesign.accent)
                            } else {
                                RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                                    .fill(RMDesign.cardBackground)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                                .stroke(periodsForward == m ? Color.clear : RMDesign.borderColor, lineWidth: 1)
                        )
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Will create")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text("\(projectedNewCount) bills")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(RMDesign.accent)
            }
            Divider().frame(height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("Total value")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(CurrencyFormatter.format(projectedCost, as: currency))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(RMDesign.success)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Divider().frame(height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("First cycle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(previewFirstDate.map { $0.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) } ?? "—")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.purple)
            }
            Spacer()
        }
        .padding(12)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(RMDesign.borderColor, lineWidth: 1)
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
            .foregroundStyle(RMDesign.accent)
            .disabled(activeTemplates.isEmpty)
        }
    }

    // MARK: - List
    private var templatesList: some View {
        VStack(spacing: 4) {
            ForEach(activeTemplates) { template in
                templateRow(template, enabled: true)
            }

            if !pausedTemplates.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(RMDesign.warning)
                    Text("Paused")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pausedTemplates.count) skipped")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
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
            withAnimation(RMDesign.ease) {
                if isSelected {
                    selectedIds.remove(template.id)
                } else {
                    selectedIds.insert(template.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: enabled
                      ? (isSelected ? "checkmark.circle.fill" : "circle")
                      : "pause.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(enabled
                                     ? (isSelected ? RMDesign.accent : .secondary)
                                     : RMDesign.warning)

                Image(systemName: template.category.iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(template.category.color)
                    .frame(width: 24, height: 24)
                    .background(template.category.color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(template.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if template.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RMDesign.warning)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    HStack(spacing: 5) {
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
                            .foregroundStyle(RMDesign.accent)
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
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(9)
            .background(enabled
                        ? (isSelected ? RMDesign.accent.opacity(0.05) : RMDesign.cardBackground)
                        : RMDesign.warning.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                    .stroke(
                        enabled
                            ? (isSelected ? RMDesign.accent.opacity(0.35) : RMDesign.borderColor)
                            : RMDesign.warning.opacity(0.25),
                        lineWidth: enabled ? (isSelected ? 1.3 : 1) : 1
                    )
            )
            .opacity(enabled ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Result
    private func resultView(_ result: FutureBillsGenerator.GenerationResult) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(RMDesign.success)

            VStack(spacing: 6) {
                Text("Generated \(result.created) new bill\(result.created == 1 ? "" : "s")")
                    .font(.system(size: 16, weight: .semibold))

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
                                .foregroundStyle(RMDesign.success)
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
                .padding(12)
                .background(RMDesign.success.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
            }
            Spacer()
        }
        .padding(20)
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
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
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
        .padding(16)
    }

    // MARK: - Run
    private func runGeneration() {
        let r = FutureBillsGenerator.generate(
            templates: selectedTemplates,
            periodsForward: periodsForward,
            context: modelContext
        )
        withAnimation(RMDesign.ease) {
            result = r
        }
    }
}