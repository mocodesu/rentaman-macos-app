import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(PreferenceKey.displayCurrency) private var currencyRaw: String = AppCurrency.ksh.rawValue
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage(PreferenceKey.dateFormatStyle) private var dateFormatRaw: String = DateFormatStyle.system.rawValue
    @AppStorage(PreferenceKey.startWeekOn) private var weekStartRaw: String = WeekStart.sunday.rawValue
    @AppStorage(PreferenceKey.showDecimals) private var showDecimals: Bool = true
    @AppStorage(PreferenceKey.enableAnimations) private var enableAnimations: Bool = true

    private var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        nonmutating set { appearanceRaw = newValue.rawValue }
    }

    private var currency: AppCurrency {
        get { AppCurrency(rawValue: currencyRaw) ?? .ksh }
        nonmutating set { currencyRaw = newValue.rawValue }
    }

    private var dateFormat: DateFormatStyle {
        get { DateFormatStyle(rawValue: dateFormatRaw) ?? .system }
        nonmutating set { dateFormatRaw = newValue.rawValue }
    }

    private var weekStart: WeekStart {
        get { WeekStart(rawValue: weekStartRaw) ?? .sunday }
        nonmutating set { weekStartRaw = newValue.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("General")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Customize how RentaMan looks and behaves.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // MARK: - Currency
                SettingsSection(title: "Display Currency", subtitle: "All amounts are stored in KES and converted on display.") {
                    VStack(spacing: 0) {
                        SettingsRow(icon: "dollarsign.circle.fill", iconColor: RMDesign.success, title: "Currency") {
                            Picker("", selection: Binding(get: { currency }, set: { currency = $0 })) {
                                ForEach(AppCurrency.allCases) { curr in
                                    Text("\(curr.symbol) \(curr.rawValue)").tag(curr)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }

                        Divider().padding(.leading, 36).padding(.vertical, 4)

                        SettingsRow(icon: "number.circle.fill", iconColor: RMDesign.accent, title: "Show decimal places", subtitle: "Display amounts like 67,000.00 instead of 67,000") {
                            Toggle("", isOn: $showDecimals)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider().padding(.leading, 36).padding(.vertical, 4)

                        HStack(spacing: 10) {
                            Image(systemName: "equal.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(RMDesign.warning)
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Preview")
                                    .font(.system(size: 12.5, weight: .medium))
                                Text("How amounts will appear")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(previewAmount)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Appearance
                SettingsSection(title: "Appearance", subtitle: "Choose your preferred look.") {
                    VStack(spacing: 0) {
                        SettingsRow(icon: "paintbrush.fill", iconColor: .purple, title: "Theme") {
                            Picker("", selection: Binding(get: { appearance }, set: { appearance = $0 })) {
                                ForEach(AppAppearance.allCases) { mode in
                                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }

                        Divider().padding(.leading, 36).padding(.vertical, 4)

                        SettingsRow(icon: "sparkles", iconColor: .pink, title: "Enable animations", subtitle: "Smooth transitions and micro-interactions") {
                            Toggle("", isOn: $enableAnimations)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }

                // MARK: - Regional
                SettingsSection(title: "Regional", subtitle: "Date and week preferences.") {
                    VStack(spacing: 0) {
                        SettingsRow(icon: "calendar", iconColor: RMDesign.danger, title: "Date format") {
                            Picker("", selection: Binding(get: { dateFormat }, set: { dateFormat = $0 })) {
                                ForEach(DateFormatStyle.allCases) { fmt in
                                    Text(fmt.rawValue).tag(fmt)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }

                        Divider().padding(.leading, 36).padding(.vertical, 4)

                        SettingsRow(icon: "calendar.badge.clock", iconColor: .indigo, title: "Week starts on") {
                            Picker("", selection: Binding(get: { weekStart }, set: { weekStart = $0 })) {
                                ForEach(WeekStart.allCases) { day in
                                    Text(day.rawValue).tag(day)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var previewAmount: String {
        let amount: Double = 67000
        let converted = CurrencyFormatter.convert(amount, to: currency)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        if showDecimals {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        let numStr = formatter.string(from: NSNumber(value: converted)) ?? "0"
        return "\(currency.symbol) \(numStr)"
    }
}