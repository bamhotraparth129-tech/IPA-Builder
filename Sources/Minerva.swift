import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Models

enum TxType: String, Codable, CaseIterable {
    case expense = "Expense"
    case income = "Income"
}

enum TxCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food & Mess"
    case travel = "Travel & Auto"
    case study = "Study & Books"
    case bills = "Bills & Recharge"
    case gaming = "Gaming & Tech"
    case salary = "Allowance / Income"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .travel: return "car.fill"
        case .study: return "book.fill"
        case .bills: return "bolt.fill"
        case .gaming: return "gamecontroller.fill"
        case .salary: return "indianrupeesign.circle.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
}

struct BudgetGoal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var limitAmount: Double
    var category: TxCategory?

    init(id: UUID = UUID(), name: String, limitAmount: Double, category: TxCategory? = nil) {
        self.id = id
        self.name = name
        self.limitAmount = limitAmount
        self.category = category
    }
}

struct TransactionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var amount: Double
    var type: TxType
    var category: TxCategory
    var date: Date
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        type: TxType,
        category: TxCategory,
        date: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.date = date
        self.note = note
    }
}

struct RupaiyaProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var transactions: [TransactionItem]
    var budgets: [BudgetGoal]

    init(
        id: UUID = UUID(),
        name: String,
        transactions: [TransactionItem] = [],
        budgets: [BudgetGoal] = []
    ) {
        self.id = id
        self.name = name
        self.transactions = transactions
        self.budgets = budgets
    }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case allTime = "All Time"
    case custom = "Custom Range"

    var id: String { rawValue }

    func dateBounds(
        now: Date = Date(),
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = .current
    ) -> (start: Date?, end: Date?) {
        switch self {
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps)
            return (start, now)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)
            return (start, now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)
            return (start, now)
        case .allTime:
            return (nil, nil)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let endDay = max(customStart, customEnd)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay
            return (start, end)
        }
    }
}

struct PDFDocumentTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            SentTransferredFile(item.url)
        }
    }
}

// MARK: - PDF Statement Generator

enum PDFExporter {
    static func generateStatement(
        profileName: String,
        transactions: [TransactionItem],
        periodLabel: String,
        from startDate: Date?,
        to endDate: Date?
    ) -> URL? {
        let filtered = transactions.filter { item in
            if let s = startDate, item.date < s { return false }
            if let e = endDate, item.date > e { return false }
            return true
        }.sorted { $0.date > $1.date }

        let totalIncome = filtered.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let totalExpense = filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let net = totalIncome - totalExpense

        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 36
        let contentWidth = pageRect.width - (margin * 2)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .medium
        dateTimeFormatter.timeStyle = .short

        let generatedStamp = dateTimeFormatter.string(from: Date())

        let data = renderer.pdfData { context in
            var currentY: CGFloat = 0

            func startNewPage() {
                context.beginPage()
                currentY = margin

                let headerRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 54)
                UIColor(red: 0.06, green: 0.24, blue: 0.19, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: headerRect, cornerRadius: 8).fill()

                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white
                ]
                NSString(string: "Rupaiya — \(profileName)").draw(
                    at: CGPoint(x: headerRect.minX + 14, y: headerRect.minY + 10),
                    withAttributes: titleAttrs
                )

                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10.5),
                    .foregroundColor: UIColor(white: 0.92, alpha: 1.0)
                ]
                NSString(string: "Period: \(periodLabel)  •  Generated: \(generatedStamp)").draw(
                    at: CGPoint(x: headerRect.minX + 14, y: headerRect.minY + 34),
                    withAttributes: subAttrs
                )

                currentY = headerRect.maxY + 16
            }

            startNewPage()

            let cardGap: CGFloat = 10
            let cardWidth = (contentWidth - (cardGap * 2)) / 3
            let cardHeight: CGFloat = 56

            let summaries: [(String, Double, UIColor)] = [
                ("Total Income", totalIncome, UIColor.systemGreen),
                ("Total Expense", totalExpense, UIColor.systemRed),
                ("Net Balance", net, net >= 0 ? UIColor.systemTeal : UIColor.systemOrange)
            ]

            for (idx, summary) in summaries.enumerated() {
                let x = margin + CGFloat(idx) * (cardWidth + cardGap)
                let rect = CGRect(x: x, y: currentY, width: cardWidth, height: cardHeight)
                UIColor(white: 0.96, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()

                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: UIColor.darkGray
                ]
                NSString(string: summary.0).draw(
                    at: CGPoint(x: rect.minX + 10, y: rect.minY + 9),
                    withAttributes: labelAttrs
                )

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: summary.2
                ]
                NSString(string: formatINR(summary.1)).draw(
                    at: CGPoint(x: rect.minX + 10, y: rect.minY + 28),
                    withAttributes: valAttrs
                )
            }

            currentY += cardHeight + 20

            let secAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]
            NSString(string: "Entries (\(filtered.count))").draw(
                at: CGPoint(x: margin, y: currentY),
                withAttributes: secAttrs
            )
            currentY += 22

            let colHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            NSString(string: "Date & Time").draw(at: CGPoint(x: margin, y: currentY), withAttributes: colHeaderAttrs)
            NSString(string: "Type").draw(at: CGPoint(x: margin + 145, y: currentY), withAttributes: colHeaderAttrs)
            NSString(string: "Title / Category").draw(at: CGPoint(x: margin + 210, y: currentY), withAttributes: colHeaderAttrs)
            NSString(string: "Amount").draw(at: CGPoint(x: pageRect.width - margin - 85, y: currentY), withAttributes: colHeaderAttrs)

            currentY += 16
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: margin, y: currentY))
            linePath.addLine(to: CGPoint(x: pageRect.width - margin, y: currentY))
            UIColor.lightGray.setStroke()
            linePath.lineWidth = 1
            linePath.stroke()
            currentY += 8

            if filtered.isEmpty {
                let emptyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.italicSystemFont(ofSize: 12),
                    .foregroundColor: UIColor.gray
                ]
                NSString(string: "No income or expense entries found for this profile and period.").draw(
                    at: CGPoint(x: margin, y: currentY + 8),
                    withAttributes: emptyAttrs
                )
                return
            }

            let rowHeight: CGFloat = 34
            for (index, item) in filtered.enumerated() {
                if currentY + rowHeight > pageRect.height - margin {
                    startNewPage()
                }

                if index % 2 == 1 {
                    let stripeRect = CGRect(x: margin, y: currentY - 2, width: contentWidth, height: rowHeight)
                    UIColor(white: 0.985, alpha: 1.0).setFill()
                    UIBezierPath(rect: stripeRect).fill()
                }

                let whenStr = dateTimeFormatter.string(from: item.date)
                let typeStr = item.type.rawValue
                let detailStr = "\(item.title) (\(item.category.rawValue))"
                let sign = item.type == .expense ? "-" : "+"
                let amountStr = "\(sign)\(formatINR(item.amount))"

                let dateAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.darkGray
                ]
                NSString(string: whenStr).draw(
                    in: CGRect(x: margin, y: currentY + 4, width: 140, height: rowHeight),
                    withAttributes: dateAttrs
                )

                let typeColor = item.type == .expense ? UIColor.systemRed : UIColor.systemGreen
                let typeAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 10),
                    .foregroundColor: typeColor
                ]
                NSString(string: typeStr).draw(
                    in: CGRect(x: margin + 145, y: currentY + 4, width: 62, height: rowHeight),
                    withAttributes: typeAttrs
                )

                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10.5, weight: .medium),
                    .foregroundColor: UIColor.black
                ]
                NSString(string: detailStr).draw(
                    in: CGRect(x: margin + 210, y: currentY + 4, width: contentWidth - 295, height: rowHeight),
                    withAttributes: titleAttrs
                )

                let amtAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 10.5),
                    .foregroundColor: typeColor
                ]
                NSString(string: amountStr).draw(
                    in: CGRect(x: pageRect.width - margin - 90, y: currentY + 4, width: 90, height: rowHeight),
                    withAttributes: amtAttrs
                )

                currentY += rowHeight
            }
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Rupaiya_\(profileName)_Statement.pdf")
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }
}

// MARK: - Store & CSV Export

final class LedgerStore: ObservableObject {
    @Published var profiles: [RupaiyaProfile] = [] {
        didSet { saveProfiles() }
    }
    @Published var activeProfileID: UUID {
        didSet { UserDefaults.standard.set(activeProfileID.uuidString, forKey: activeProfileKey) }
    }

    private let profilesURL: URL
    private let activeProfileKey = "rupaiya_active_profile_id"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.profilesURL = docs.appendingPathComponent("rupeeflow_profiles.json")

        let loadedProfiles = Self.loadProfilesFromDisk(url: profilesURL)
        self.profiles = loadedProfiles

        if let savedIDString = UserDefaults.standard.string(forKey: activeProfileKey),
           let savedUUID = UUID(uuidString: savedIDString),
           loadedProfiles.contains(where: { $0.id == savedUUID }) {
            self.activeProfileID = savedUUID
        } else {
            self.activeProfileID = loadedProfiles.first?.id ?? UUID()
        }
    }

    var activeProfileIndex: Int {
        if let idx = profiles.firstIndex(where: { $0.id == activeProfileID }) {
            return idx
        }
        return 0
    }

    var activeProfile: RupaiyaProfile {
        profiles[activeProfileIndex]
    }

    var activeProfileName: String {
        activeProfile.name
    }

    var transactions: [TransactionItem] {
        activeProfile.transactions
    }

    var budgets: [BudgetGoal] {
        activeProfile.budgets
    }

    func selectProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    func addProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newProfile = RupaiyaProfile(
            name: trimmed,
            transactions: [],
            budgets: [BudgetGoal(name: "Monthly Spend", limitAmount: 10000, category: nil)]
        )
        profiles.append(newProfile)
        activeProfileID = newProfile.id
    }

    func renameActiveProfile(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, profiles.indices.contains(activeProfileIndex) else { return }
        profiles[activeProfileIndex].name = trimmed
    }

    func deleteProfile(at offsets: IndexSet) {
        guard profiles.count > offsets.count else { return }
        let removingActive = offsets.contains { profiles.indices.contains($0) && profiles[$0].id == activeProfileID }
        profiles.remove(atOffsets: offsets)
        if profiles.isEmpty {
            let fallback = RupaiyaProfile(name: "Personal")
            profiles = [fallback]
            activeProfileID = fallback.id
        } else if removingActive {
            activeProfileID = profiles[0].id
        }
    }

    var currentMonthExpenses: Double {
        let cal = Calendar.current
        let now = Date()
        return transactions
            .filter { $0.type == .expense && cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var currentMonthIncome: Double {
        let cal = Calendar.current
        let now = Date()
        return transactions
            .filter { $0.type == .income && cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var netBalance: Double {
        transactions.reduce(0) { total, item in
            item.type == .income ? total + item.amount : total - item.amount
        }
    }

    func spentAmount(for budget: BudgetGoal) -> Double {
        let cal = Calendar.current
        let now = Date()
        return transactions
            .filter { item in
                guard item.type == .expense,
                      cal.isDate(item.date, equalTo: now, toGranularity: .month) else {
                    return false
                }
                if let cat = budget.category {
                    return item.category == cat
                }
                return true
            }
            .reduce(0) { $0 + $1.amount }
    }

    func addBudget(name: String, limitAmount: Double, category: TxCategory?) {
        guard limitAmount > 0, profiles.indices.contains(activeProfileIndex) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? (category?.rawValue ?? "General Budget") : trimmed
        profiles[activeProfileIndex].budgets.append(
            BudgetGoal(name: finalName, limitAmount: limitAmount, category: category)
        )
    }

    func deleteBudgets(at offsets: IndexSet) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        profiles[activeProfileIndex].budgets.remove(atOffsets: offsets)
    }

    func categoryTotals(type: TxType = .expense) -> [(category: TxCategory, total: Double)] {
        let filtered = transactions.filter { $0.type == type }
        var map: [TxCategory: Double] = [:]
        for item in filtered {
            map[item.category, default: 0] += item.amount
        }
        return map
            .map { (category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    func addTransaction(title: String, amount: Double, type: TxType, category: TxCategory, note: String) {
        guard amount > 0, profiles.indices.contains(activeProfileIndex) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = TransactionItem(
            title: cleanTitle.isEmpty ? category.rawValue : cleanTitle,
            amount: amount,
            type: type,
            category: category,
            date: Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profiles[activeProfileIndex].transactions.insert(item, at: 0)
    }

    func delete(at offsets: IndexSet) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        profiles[activeProfileIndex].transactions.remove(atOffsets: offsets)
    }

    func exportCSV() -> String {
        var rows = ["Profile,Date_Time,Title,Type,Category,Amount_INR,Note"]
        let formatter = ISO8601DateFormatter()
        let safeProfile = activeProfileName.replacingOccurrences(of: "\"", with: "\"\"")
        for t in transactions {
            let escapedTitle = t.title.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedNote = t.note.replacingOccurrences(of: "\"", with: "\"\"")
            rows.append("\"\(safeProfile)\",\"\(formatter.string(from: t.date))\",\"\(escapedTitle)\",\"\(t.type.rawValue)\",\"\(t.category.rawValue)\",\(String(format: "%.2f", t.amount)),\"\(escapedNote)\"")
        }
        return rows.joined(separator: "\n")
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: profilesURL, options: .atomic)
        }
    }

    private static func loadProfilesFromDisk(url: URL) -> [RupaiyaProfile] {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([RupaiyaProfile].self, from: data),
           !decoded.isEmpty {
            return decoded
        }

        let docs = url.deletingLastPathComponent()
        let legacyTxURL = docs.appendingPathComponent("rupeeflow_transactions.json")
        let legacyBudgetsURL = docs.appendingPathComponent("rupeeflow_budgets.json")

        let legacyTx: [TransactionItem] = {
            if let data = try? Data(contentsOf: legacyTxURL),
               let decoded = try? JSONDecoder().decode([TransactionItem].self, from: data) {
                return decoded
            }
            return [
                TransactionItem(title: "Monthly Allowance", amount: 12000, type: .income, category: .salary, note: "Starter entry"),
                TransactionItem(title: "Lunch & Chai", amount: 180, type: .expense, category: .food, note: "Sample expense")
            ]
        }()

        let legacyBudgets: [BudgetGoal] = {
            if let data = try? Data(contentsOf: legacyBudgetsURL),
               let decoded = try? JSONDecoder().decode([BudgetGoal].self, from: data) {
                return decoded
            }
            return [
                BudgetGoal(name: "Monthly Spend", limitAmount: 10000, category: nil),
                BudgetGoal(name: "Food & Mess", limitAmount: 4000, category: .food),
                BudgetGoal(name: "Travel & Auto", limitAmount: 2000, category: .travel)
            ]
        }()

        return [
            RupaiyaProfile(name: "Personal", transactions: legacyTx, budgets: legacyBudgets)
        ]
    }
}

// MARK: - Formatting Helper

func formatINR(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? "₹\(value)"
}

// MARK: - Profile Switcher & Manager Sheet

struct ProfileManagerSheet: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var newProfileName = ""
    @State private var renameDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add New Person / Profile") {
                    TextField("Person or profile name (e.g., Papa, Mom, Roommate)", text: $newProfileName)
                    Button("Create Profile") {
                        store.addProfile(name: newProfileName)
                        newProfileName = ""
                    }
                    .bold()
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Active Profile Name") {
                    TextField("Rename active profile", text: $renameDraft)
                    Button("Save Name") {
                        store.renameActiveProfile(to: renameDraft)
                    }
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("All Profiles (Tap to Switch)") {
                    ForEach(store.profiles) { profile in
                        Button {
                            store.selectProfile(id: profile.id)
                            renameDraft = profile.name
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(profile.transactions.count) entries")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == store.activeProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .onDelete(perform: store.deleteProfile)
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                renameDraft = store.activeProfileName
            }
            .onChange(of: store.activeProfileID) { _ in
                renameDraft = store.activeProfileName
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Views

struct LedgerHomeView: View {
    @ObservedObject var store: LedgerStore
    @State private var showingAddSheet = false
    @State private var showingProfileSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Picker("Profile", selection: $store.activeProfileID) {
                            ForEach(store.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()

                        Button {
                            showingProfileSheet = true
                        } label: {
                            Label("Profiles", systemImage: "person.2.badge.plus")
                                .font(.subheadline.bold())
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(store.activeProfileName) — Net Balance")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(formatINR(store.netBalance))
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        HStack {
                            Label("In: \(formatINR(store.currentMonthIncome))", systemImage: "arrow.down.left.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline.bold())
                            Spacer()
                            Label("Out: \(formatINR(store.currentMonthExpenses))", systemImage: "arrow.up.right.circle.fill")
                                .foregroundStyle(.red)
                                .font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !store.budgets.isEmpty {
                    Section("Named Budgets (This Month)") {
                        ForEach(store.budgets) { budget in
                            let spent = store.spentAmount(for: budget)
                            let ratio = budget.limitAmount > 0 ? spent / budget.limitAmount : 0

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(budget.name)
                                        .font(.subheadline.bold())
                                    if let cat = budget.category {
                                        Text("• \(cat.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(formatINR(spent)) / \(formatINR(budget.limitAmount))")
                                        .font(.caption.bold())
                                }
                                ProgressView(value: min(ratio, 1.0))
                                    .tint(ratio > 1.0 ? .red : .green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Recent Activity") {
                    if store.transactions.isEmpty {
                        Text("No entries yet for \(store.activeProfileName). Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.transactions) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.category.icon)
                                    .font(.title3)
                                    .foregroundStyle(item.type == .expense ? .red : .green)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text("\(item.category.rawValue) • \(item.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("\(item.type == .expense ? "-" : "+")\(formatINR(item.amount))")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(item.type == .expense ? .red : .green)
                            }
                            .padding(.vertical, 3)
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .navigationTitle("Rupaiya")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingProfileSheet = true
                    } label: {
                        Text(store.activeProfileName)
                            .font(.subheadline.bold())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddTransactionSheet(store: store)
            }
            .sheet(isPresented: $showingProfileSheet) {
                ProfileManagerSheet(store: store)
            }
        }
    }
}

struct AddTransactionSheet: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: TxType = .expense
    @State private var title = ""
    @State private var amountText = ""
    @State private var category: TxCategory = .food
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    Text("Adding to: \(store.activeProfileName)")
                        .font(.subheadline.bold())
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(TxType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { newType in
                        category = newType == .income ? .salary : .food
                    }
                }

                Section("Details") {
                    TextField("Amount in ₹", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Title (e.g., Metro, Mess, Notebook)", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(TxCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    TextField("Optional note", text: $note)
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
                        if let val = Double(cleaned), val > 0 {
                            store.addTransaction(title: title, amount: val, type: type, category: category, note: note)
                            dismiss()
                        }
                    }
                    .bold()
                }
            }
        }
    }
}

struct BreakdownView: View {
    @ObservedObject var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                Section("Spending by Category (\(store.activeProfileName))") {
                    let items = store.categoryTotals(type: .expense)
                    let maxVal = max(items.first?.total ?? 1, 1)

                    if items.isEmpty {
                        Text("No expense data yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items, id: \.category) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(entry.category.rawValue, systemImage: entry.category.icon)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(formatINR(entry.total))
                                        .font(.subheadline.bold())
                                }
                                ProgressView(value: entry.total / maxVal)
                                    .tint(.blue)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("Breakdown")
        }
    }
}

struct BudgetSettingsView: View {
    @ObservedObject var store: LedgerStore

    @State private var budgetName: String = ""
    @State private var budgetLimitInput: String = ""
    @State private var selectedCategory: TxCategory? = nil

    @State private var selectedPeriod: ReportPeriod = .thisMonth
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    @State private var generatedPDF: PDFDocumentTransfer?
    @State private var showingProfileSheet = false

    private var activePeriodLabel: String {
        if selectedPeriod == .custom {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            let a = min(customStartDate, customEndDate)
            let b = max(customStartDate, customEndDate)
            return "\(fmt.string(from: a)) – \(fmt.string(from: b))"
        }
        return selectedPeriod.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Active Profile") {
                    HStack {
                        Text(store.activeProfileName)
                            .font(.headline)
                        Spacer()
                        Button("Manage Profiles") {
                            showingProfileSheet = true
                        }
                    }
                }

                Section("Add Named Budget (\(store.activeProfileName))") {
                    TextField("Budget name (e.g., Mess, Travel, Gaming)", text: $budgetName)
                    TextField("Limit amount in ₹", text: $budgetLimitInput)
                        .keyboardType(.decimalPad)
                    Picker("Scope", selection: $selectedCategory) {
                        Text("All Expenses").tag(TxCategory?.none)
                        ForEach(TxCategory.allCases) { cat in
                            Text(cat.rawValue).tag(Optional(cat))
                        }
                    }
                    Button("Add Budget") {
                        let cleaned = budgetLimitInput.replacingOccurrences(of: ",", with: "")
                        if let val = Double(cleaned), val > 0 {
                            store.addBudget(name: budgetName, limitAmount: val, category: selectedCategory)
                            budgetName = ""
                            budgetLimitInput = ""
                            selectedCategory = nil
                        }
                    }
                    .bold()
                }

                Section("Your Named Budgets") {
                    if store.budgets.isEmpty {
                        Text("No named budgets created yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.budgets) { budget in
                            let spent = store.spentAmount(for: budget)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(budget.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("Limit: \(formatINR(budget.limitAmount))")
                                        .font(.subheadline.bold())
                                }
                                HStack {
                                    Text(budget.category?.rawValue ?? "All Expenses")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Spent: \(formatINR(spent))")
                                        .font(.caption)
                                        .foregroundStyle(spent > budget.limitAmount ? .red : .secondary)
                                }
                            }
                        }
                        .onDelete(perform: store.deleteBudgets)
                    }
                }

                Section("PDF Statement (\(store.activeProfileName))") {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(ReportPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .onChange(of: selectedPeriod) { _ in
                        generatedPDF = nil
                    }

                    if selectedPeriod == .custom {
                        DatePicker("From Date", selection: $customStartDate, displayedComponents: .date)
                            .onChange(of: customStartDate) { _ in generatedPDF = nil }
                        DatePicker("To Date", selection: $customEndDate, displayedComponents: .date)
                            .onChange(of: customEndDate) { _ in generatedPDF = nil }
                    }

                    Button {
                        let bounds = selectedPeriod.dateBounds(
                            customStart: customStartDate,
                            customEnd: customEndDate
                        )
                        if let url = PDFExporter.generateStatement(
                            profileName: store.activeProfileName,
                            transactions: store.transactions,
                            periodLabel: activePeriodLabel,
                            from: bounds.start,
                            to: bounds.end
                        ) {
                            generatedPDF = PDFDocumentTransfer(url: url)
                        }
                    } label: {
                        Label("Generate PDF Statement", systemImage: "doc.richtext.fill")
                    }

                    if let pdfItem = generatedPDF {
                        ShareLink(
                            item: pdfItem,
                            preview: SharePreview("Rupaiya_\(store.activeProfileName)_Statement.pdf", image: Image(systemName: "doc.richtext.fill"))
                        ) {
                            Label("Share / Save PDF", systemImage: "square.and.arrow.up")
                                .bold()
                        }
                    }
                }

                Section("Export CSV (\(store.activeProfileName))") {
                    ShareLink(item: store.exportCSV()) {
                        Label("Export Transactions CSV", systemImage: "tablecells")
                    }
                }
            }
            .navigationTitle("Budget & Export")
            .onChange(of: store.activeProfileID) { _ in
                generatedPDF = nil
            }
            .sheet(isPresented: $showingProfileSheet) {
                ProfileManagerSheet(store: store)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var store = LedgerStore()

    var body: some View {
        TabView {
            LedgerHomeView(store: store)
                .tabItem {
                    Label("Ledger", systemImage: "indianrupeesign.circle")
                }

            BreakdownView(store: store)
                .tabItem {
                    Label("Breakdown", systemImage: "chart.bar.fill")
                }

            BudgetSettingsView(store: store)
                .tabItem {
                    Label("Budget", systemImage: "slider.horizontal.3")
                }
        }
    }
}

@main
struct RupaiyaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
