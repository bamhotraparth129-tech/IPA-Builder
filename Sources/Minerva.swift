import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication
import UIKit

// MARK: - Models

enum TxType: String, Codable, CaseIterable {
    case expense = "Expense"
    case income = "Income"
}

enum PaymentMode: String, Codable, CaseIterable, Identifiable {
    case upi = "UPI"
    case cash = "Cash"
    case card = "Card"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .upi: return "qrcode"
        case .cash: return "banknote"
        case .card: return "creditcard"
        }
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"

    var id: String { rawValue }

    func nextDate(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

enum TxCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food & Mess"
    case travel = "Travel & Auto"
    case study = "Study & Books"
    case bills = "Bills & Recharge"
    case gaming = "Gaming & Tech"
    case transfer = "Profile Transfer"
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
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .salary: return "indianrupeesign.circle.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    static func matching(rawOrHint: String?) -> TxCategory {
        guard let hint = rawOrHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !hint.isEmpty else {
            return .other
        }
        if let exact = TxCategory.allCases.first(where: { $0.rawValue.lowercased() == hint }) {
            return exact
        }
        if hint.contains("food") || hint.contains("swiggy") || hint.contains("zomato") || hint.contains("blinkit") || hint.contains("zepto") || hint.contains("mess") {
            return .food
        }
        if hint.contains("travel") || hint.contains("uber") || hint.contains("ola") || hint.contains("metro") || hint.contains("auto") {
            return .travel
        }
        if hint.contains("study") || hint.contains("book") || hint.contains("course") {
            return .study
        }
        if hint.contains("bill") || hint.contains("recharge") || hint.contains("electricity") {
            return .bills
        }
        if hint.contains("game") || hint.contains("gaming") || hint.contains("amazon") || hint.contains("flipkart") || hint.contains("shop") {
            return .gaming
        }
        return .other
    }
}

struct RecurringBill: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var amount: Double
    var category: TxCategory
    var paymentMode: PaymentMode
    var frequency: RecurrenceFrequency
    var nextDueDate: Date
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        category: TxCategory = .bills,
        paymentMode: PaymentMode = .upi,
        frequency: RecurrenceFrequency = .monthly,
        nextDueDate: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.paymentMode = paymentMode
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.note = note
    }
}

struct QuickExpenseDraft: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var amountText: String
    var category: TxCategory
    var note: String
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
    var paymentMode: PaymentMode
    var date: Date
    var note: String

    init(
        id: UUID = UUID(),
        title: String,
        amount: Double,
        type: TxType,
        category: TxCategory,
        paymentMode: PaymentMode = .upi,
        date: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.paymentMode = paymentMode
        self.date = date
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, title, amount, type, category, paymentMode, date, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        amount = try c.decode(Double.self, forKey: .amount)
        type = try c.decode(TxType.self, forKey: .type)
        category = try c.decode(TxCategory.self, forKey: .category)
        paymentMode = try c.decodeIfPresent(PaymentMode.self, forKey: .paymentMode) ?? .upi
        date = try c.decode(Date.self, forKey: .date)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct RupaiyaProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var transactions: [TransactionItem]
    var budgets: [BudgetGoal]
    var recurringBills: [RecurringBill]

    init(
        id: UUID = UUID(),
        name: String,
        transactions: [TransactionItem] = [],
        budgets: [BudgetGoal] = [],
        recurringBills: [RecurringBill] = []
    ) {
        self.id = id
        self.name = name
        self.transactions = transactions
        self.budgets = budgets
        self.recurringBills = recurringBills
    }

    enum CodingKeys: String, CodingKey {
        case id, name, transactions, budgets, recurringBills
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        transactions = try c.decodeIfPresent([TransactionItem].self, forKey: .transactions) ?? []
        budgets = try c.decodeIfPresent([BudgetGoal].self, forKey: .budgets) ?? []
        recurringBills = try c.decodeIfPresent([RecurringBill].self, forKey: .recurringBills) ?? []
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

// MARK: - Privacy Biometric / Passcode Manager

final class PrivacyLockManager: ObservableObject {
    @Published var isPrivacyHidden: Bool = false
    @Published var authErrorMessage: String?

    func togglePrivacy() {
        if !isPrivacyHidden {
            isPrivacyHidden = true
            authErrorMessage = nil
        } else {
            authenticateToReveal()
        }
    }

    func lockIfNeeded() {
        isPrivacyHidden = true
    }

    func authenticateToReveal() {
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock hidden ₹ balances and transactions in Rupaiya"

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
                DispatchQueue.main.async {
                    if success {
                        self.isPrivacyHidden = false
                        self.authErrorMessage = nil
                    } else {
                        self.authErrorMessage = evalError?.localizedDescription ?? "Authentication cancelled."
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isPrivacyHidden = false
                self.authErrorMessage = nil
            }
        }
    }
}

// MARK: - Deep Link / Shortcut Parser

enum RupaiyaDeepLink {
    static func parseQuickExpense(from url: URL) -> QuickExpenseDraft? {
        guard url.scheme?.lowercased() == "rupaiya" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = comps?.queryItems ?? []

        func value(for key: String) -> String? {
            queryItems.first(where: { $0.name.lowercased() == key.lowercased() })?.value
        }

        let title = value(for: "title") ?? value(for: "app") ?? value(for: "merchant") ?? "Order Expense"
        let amountRaw = value(for: "amount") ?? ""
        let categoryHint = value(for: "category") ?? title
        let note = value(for: "note") ?? "Logged via quick order prompt"

        return QuickExpenseDraft(
            title: title,
            amountText: amountRaw,
            category: TxCategory.matching(rawOrHint: categoryHint),
            note: note
        )
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
        let margin: CGFloat = 32
        let contentWidth = pageRect.width - (margin * 2)

        // Column X offsets and widths across contentWidth (531.2pt)
        let dateX: CGFloat = margin
        let dateW: CGFloat = 104
        let modeX: CGFloat = dateX + dateW + 4
        let modeW: CGFloat = 62
        let entryX: CGFloat = modeX + modeW + 4
        let entryW: CGFloat = 148
        let notesX: CGFloat = entryX + entryW + 6
        let notesW: CGFloat = 123
        let amtX: CGFloat = notesX + notesW + 4
        let amtW: CGFloat = (margin + contentWidth) - amtX

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .short
        dateTimeFormatter.timeStyle = .short

        let stampFormatter = DateFormatter()
        stampFormatter.dateStyle = .medium
        stampFormatter.timeStyle = .short
        let generatedStamp = stampFormatter.string(from: Date())

        let data = renderer.pdfData { context in
            var currentY: CGFloat = 0

            func ensureSpace(_ neededHeight: CGFloat) {
                if currentY + neededHeight > pageRect.height - margin {
                    startNewPage()
                }
            }

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
                .font: UIFont.boldSystemFont(ofSize: 9.5),
                .foregroundColor: UIColor.darkGray
            ]
            NSString(string: "Date").draw(at: CGPoint(x: dateX, y: currentY), withAttributes: colHeaderAttrs)
            NSString(string: "Mode").draw(at: CGPoint(x: modeX, y: currentY), withAttributes: colHeaderAttrs)
            NSString(string: "Entry").draw(at: CGPoint(x: entryX, y: currentY), withAttributes: colHeaderAttrs)
            NSString(string: "Notes").draw(at: CGPoint(x: notesX, y: currentY), withAttributes: colHeaderAttrs)

            let amtHeaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 9.5),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: {
                    let p = NSMutableParagraphStyle()
                    p.alignment = .right
                    return p
                }()
            ]
            NSString(string: "Amount").draw(
                in: CGRect(x: amtX, y: currentY, width: amtW, height: 14),
                withAttributes: amtHeaderAttrs
            )

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
            } else {
                let rightAlignStyle = NSMutableParagraphStyle()
                rightAlignStyle.alignment = .right

                for (index, item) in filtered.enumerated() {
                    let trimmedNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
                    let noteCellText = trimmedNote.isEmpty ? "—" : trimmedNote
                    let entryCellText = "\(item.title) (\(item.category.rawValue))"

                    let noteAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9),
                        .foregroundColor: trimmedNote.isEmpty ? UIColor.lightGray : UIColor.darkGray
                    ]
                    let noteBounding = NSString(string: noteCellText).boundingRect(
                        with: CGSize(width: notesW, height: 60),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: noteAttrs,
                        context: nil
                    )
                    let rowHeight: CGFloat = max(30, ceil(noteBounding.height) + 12)
                    ensureSpace(rowHeight + 4)

                    if index % 2 == 1 {
                        let stripeRect = CGRect(x: margin, y: currentY - 2, width: contentWidth, height: rowHeight)
                        UIColor(white: 0.985, alpha: 1.0).setFill()
                        UIBezierPath(rect: stripeRect).fill()
                    }

                    let whenStr = dateTimeFormatter.string(from: item.date)
                    let sign = item.type == .expense ? "-" : "+"
                    let amountStr = "\(sign)\(formatINR(item.amount))"
                    let typeColor = item.type == .expense ? UIColor.systemRed : UIColor.systemGreen

                    let dateAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9),
                        .foregroundColor: UIColor.darkGray
                    ]
                    NSString(string: whenStr).draw(
                        in: CGRect(x: dateX, y: currentY + 4, width: dateW, height: rowHeight - 4),
                        withAttributes: dateAttrs
                    )

                    let modeAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                        .foregroundColor: UIColor.darkGray
                    ]
                    NSString(string: item.paymentMode.rawValue).draw(
                        in: CGRect(x: modeX, y: currentY + 4, width: modeW, height: rowHeight - 4),
                        withAttributes: modeAttrs
                    )

                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9.5, weight: .medium),
                        .foregroundColor: UIColor.black
                    ]
                    NSString(string: entryCellText).draw(
                        in: CGRect(x: entryX, y: currentY + 4, width: entryW, height: rowHeight - 4),
                        withAttributes: titleAttrs
                    )

                    NSString(string: noteCellText).draw(
                        in: CGRect(x: notesX, y: currentY + 4, width: notesW, height: rowHeight - 4),
                        withAttributes: noteAttrs
                    )

                    let amtAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 9.5),
                        .foregroundColor: typeColor,
                        .paragraphStyle: rightAlignStyle
                    ]
                    NSString(string: amountStr).draw(
                        in: CGRect(x: amtX, y: currentY + 4, width: amtW, height: rowHeight - 4),
                        withAttributes: amtAttrs
                    )

                    currentY += rowHeight
                }
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
    @Published var quickExpenseDraft: QuickExpenseDraft?

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
        activeProfile.transactions.sorted { $0.date > $1.date }
    }

    var budgets: [BudgetGoal] {
        activeProfile.budgets
    }

    var recurringBills: [RecurringBill] {
        activeProfile.recurringBills.sorted { $0.nextDueDate < $1.nextDueDate }
    }

    var dueRecurringBills: [RecurringBill] {
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        return recurringBills.filter { $0.nextDueDate <= endOfToday }
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
            budgets: [BudgetGoal(name: "Monthly Spend", limitAmount: 10000, category: nil)],
            recurringBills: []
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

    // Recurring Bills
    func addRecurringBill(
        title: String,
        amount: Double,
        category: TxCategory,
        paymentMode: PaymentMode,
        frequency: RecurrenceFrequency,
        nextDueDate: Date,
        note: String
    ) {
        guard amount > 0, profiles.indices.contains(activeProfileIndex) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bill = RecurringBill(
            title: cleanTitle.isEmpty ? category.rawValue : cleanTitle,
            amount: amount,
            category: category,
            paymentMode: paymentMode,
            frequency: frequency,
            nextDueDate: nextDueDate,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profiles[activeProfileIndex].recurringBills.append(bill)
    }

    func logRecurringBill(_ bill: RecurringBill) {
        guard profiles.indices.contains(activeProfileIndex),
              let billIdx = profiles[activeProfileIndex].recurringBills.firstIndex(where: { $0.id == bill.id }) else { return }

        let noteText = bill.note.isEmpty ? "Recurring (\(bill.frequency.rawValue))" : "\(bill.note) • Recurring (\(bill.frequency.rawValue))"
        addTransaction(
            title: bill.title,
            amount: bill.amount,
            type: .expense,
            category: bill.category,
            paymentMode: bill.paymentMode,
            date: Date(),
            note: noteText
        )

        let updatedDue = bill.frequency.nextDate(from: max(bill.nextDueDate, Date()))
        profiles[activeProfileIndex].recurringBills[billIdx].nextDueDate = updatedDue
    }

    func deleteRecurringBills(at offsets: IndexSet) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        let sortedList = recurringBills
        let idsToDelete = offsets.compactMap { sortedList.indices.contains($0) ? sortedList[$0].id : nil }
        profiles[activeProfileIndex].recurringBills.removeAll { idsToDelete.contains($0.id) }
    }

    // Profile-to-Profile Transfer
    func transferBetweenProfiles(
        fromProfileID: UUID,
        toProfileID: UUID,
        amount: Double,
        paymentMode: PaymentMode,
        date: Date,
        note: String
    ) {
        guard amount > 0,
              fromProfileID != toProfileID,
              let fromIdx = profiles.firstIndex(where: { $0.id == fromProfileID }),
              let toIdx = profiles.firstIndex(where: { $0.id == toProfileID }) else { return }

        let fromName = profiles[fromIdx].name
        let toName = profiles[toIdx].name
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let outgoing = TransactionItem(
            title: "Transfer to \(toName)",
            amount: amount,
            type: .expense,
            category: .transfer,
            paymentMode: paymentMode,
            date: date,
            note: trimmedNote.isEmpty ? "Sent to \(toName)" : trimmedNote
        )

        let incoming = TransactionItem(
            title: "Transfer from \(fromName)",
            amount: amount,
            type: .income,
            category: .transfer,
            paymentMode: paymentMode,
            date: date,
            note: trimmedNote.isEmpty ? "Received from \(fromName)" : trimmedNote
        )

        profiles[fromIdx].transactions.insert(outgoing, at: 0)
        profiles[toIdx].transactions.insert(incoming, at: 0)
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

    func addTransaction(
        title: String,
        amount: Double,
        type: TxType,
        category: TxCategory,
        paymentMode: PaymentMode = .upi,
        date: Date = Date(),
        note: String
    ) {
        guard amount > 0, profiles.indices.contains(activeProfileIndex) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = TransactionItem(
            title: cleanTitle.isEmpty ? category.rawValue : cleanTitle,
            amount: amount,
            type: type,
            category: category,
            paymentMode: paymentMode,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        profiles[activeProfileIndex].transactions.insert(item, at: 0)
    }

    func delete(at offsets: IndexSet) {
        guard profiles.indices.contains(activeProfileIndex) else { return }
        let sortedList = transactions
        let idsToDelete = offsets.compactMap { sortedList.indices.contains($0) ? sortedList[$0].id : nil }
        profiles[activeProfileIndex].transactions.removeAll { idsToDelete.contains($0.id) }
    }

    func exportCSV() -> String {
        var rows = ["Profile,Date_Time,Title,Type,Category,Payment_Mode,Amount_INR,Note"]
        let formatter = ISO8601DateFormatter()
        let safeProfile = activeProfileName.replacingOccurrences(of: "\"", with: "\"\"")
        for t in transactions {
            let escapedTitle = t.title.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedNote = t.note.replacingOccurrences(of: "\"", with: "\"\"")
            rows.append("\"\(safeProfile)\",\"\(formatter.string(from: t.date))\",\"\(escapedTitle)\",\"\(t.type.rawValue)\",\"\(t.category.rawValue)\",\"\(t.paymentMode.rawValue)\",\(String(format: "%.2f", t.amount)),\"\(escapedNote)\"")
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
                TransactionItem(title: "Monthly Allowance", amount: 12000, type: .income, category: .salary, paymentMode: .upi, note: "Starter entry"),
                TransactionItem(title: "Lunch & Chai", amount: 180, type: .expense, category: .food, paymentMode: .cash, note: "Sample expense")
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
            RupaiyaProfile(
                name: "Personal",
                transactions: legacyTx,
                budgets: legacyBudgets,
                recurringBills: [
                    RecurringBill(title: "Mobile Recharge", amount: 299, category: .bills, paymentMode: .upi, frequency: .monthly, nextDueDate: Date(), note: "Prepaid plan")
                ]
            )
        ]
    }
}

// MARK: - Formatting Helpers

func formatINR(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? "₹\(value)"
}

func displayINR(_ value: Double, hidden: Bool, prefix: String = "") -> String {
    if hidden {
        return "\(prefix)₹••••"
    }
    return "\(prefix)\(formatINR(value))"
}

// MARK: - Profile-to-Profile Transfer Sheet

struct ProfileTransferSheet: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var fromID: UUID
    @State private var toID: UUID
    @State private var amountText: String = ""
    @State private var paymentMode: PaymentMode = .upi
    @State private var transferDate: Date = Date()
    @State private var note: String = ""

    init(store: LedgerStore) {
        self.store = store
        let first = store.activeProfileID
        let second = store.profiles.first(where: { $0.id != first })?.id ?? first
        _fromID = State(initialValue: first)
        _toID = State(initialValue: second)
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.profiles.count < 2 {
                    Section {
                        Text("Create at least 2 profiles in Profiles first to transfer between people.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Transfer Direction") {
                        Picker("From Profile", selection: $fromID) {
                            ForEach(store.profiles) { p in
                                Text(p.name).tag(p.id)
                            }
                        }
                        Picker("To Profile", selection: $toID) {
                            ForEach(store.profiles) { p in
                                Text(p.name).tag(p.id)
                            }
                        }
                    }

                    Section("Transfer Details") {
                        TextField("Amount in ₹", text: $amountText)
                            .keyboardType(.decimalPad)
                        Picker("Payment Mode", selection: $paymentMode) {
                            ForEach(PaymentMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        DatePicker("Date & Time", selection: $transferDate)
                        TextField("Optional note (e.g., Split dinner, Cash given)", text: $note)
                    }
                }
            }
            .navigationTitle("Profile Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") {
                        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
                        if let val = Double(cleaned), val > 0, fromID != toID {
                            store.transferBetweenProfiles(
                                fromProfileID: fromID,
                                toProfileID: toID,
                                amount: val,
                                paymentMode: paymentMode,
                                date: transferDate,
                                note: note
                            )
                            dismiss()
                        }
                    }
                    .bold()
                    .disabled(store.profiles.count < 2 || fromID == toID)
                }
            }
        }
    }
}

// MARK: - Quick Order / Shortcut Popup Sheet

struct QuickExpenseSheet: View {
    @ObservedObject var store: LedgerStore
    let initialDraft: QuickExpenseDraft
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amountText: String
    @State private var category: TxCategory
    @State private var paymentMode: PaymentMode = .upi
    @State private var txDate: Date = Date()
    @State private var note: String

    private let quickAmounts = ["99", "199", "299", "499", "999"]

    init(store: LedgerStore, draft: QuickExpenseDraft) {
        self.store = store
        self.initialDraft = draft
        _title = State(initialValue: draft.title)
        _amountText = State(initialValue: draft.amountText)
        _category = State(initialValue: draft.category)
        _note = State(initialValue: draft.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick Amount (₹)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickAmounts, id: \.self) { preset in
                                Button("₹\(preset)") {
                                    amountText = preset
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Enter amount in ₹", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("Details (\(store.activeProfileName))") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(TxCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    Picker("Payment Mode", selection: $paymentMode) {
                        ForEach(PaymentMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date & Time", selection: $txDate)
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle("Quick Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Expense") {
                        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
                        if let val = Double(cleaned), val > 0 {
                            store.addTransaction(
                                title: title,
                                amount: val,
                                type: .expense,
                                category: category,
                                paymentMode: paymentMode,
                                date: txDate,
                                note: note
                            )
                            dismiss()
                        }
                    }
                    .bold()
                }
            }
        }
    }
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
    @ObservedObject var privacyLock: PrivacyLockManager

    @State private var showingAddSheet = false
    @State private var showingProfileSheet = false
    @State private var showingTransferSheet = false

    var body: some View {
        NavigationStack {
            List {
                if let err = privacyLock.authErrorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

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
                            showingTransferSheet = true
                        } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right")
                                .font(.subheadline.bold())
                        }

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
                        HStack {
                            Text("\(store.activeProfileName) — Net Balance")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if privacyLock.isPrivacyHidden {
                                Label("Locked", systemImage: "lock.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            }
                        }

                        Text(displayINR(store.netBalance, hidden: privacyLock.isPrivacyHidden))
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        HStack {
                            Label(
                                "In: \(displayINR(store.currentMonthIncome, hidden: privacyLock.isPrivacyHidden))",
                                systemImage: "arrow.down.left.circle.fill"
                            )
                            .foregroundStyle(.green)
                            .font(.subheadline.bold())
                            Spacer()
                            Label(
                                "Out: \(displayINR(store.currentMonthExpenses, hidden: privacyLock.isPrivacyHidden))",
                                systemImage: "arrow.up.right.circle.fill"
                            )
                            .foregroundStyle(.red)
                            .font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !store.dueRecurringBills.isEmpty {
                    Section("Due Recurring Bills") {
                        ForEach(store.dueRecurringBills) { bill in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.title)
                                        .font(.subheadline.bold())
                                    Text("\(bill.frequency.rawValue) • \(bill.paymentMode.rawValue) • Due \(bill.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(displayINR(bill.amount, hidden: privacyLock.isPrivacyHidden))
                                    .font(.subheadline.bold())
                                Button("Log Now") {
                                    store.logRecurringBill(bill)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
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
                                    Text("\(displayINR(spent, hidden: privacyLock.isPrivacyHidden)) / \(displayINR(budget.limitAmount, hidden: privacyLock.isPrivacyHidden))")
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
                            let trimmedNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
                            let sign = item.type == .expense ? "-" : "+"

                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.category.icon)
                                    .font(.title3)
                                    .foregroundStyle(item.type == .expense ? .red : .green)
                                    .frame(width: 28)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text("\(item.category.rawValue) • \(item.paymentMode.rawValue) • \(item.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !trimmedNote.isEmpty {
                                        Text(trimmedNote)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .padding(.top, 1)
                                    }
                                }

                                Spacer()

                                Text(displayINR(item.amount, hidden: privacyLock.isPrivacyHidden, prefix: sign))
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        privacyLock.togglePrivacy()
                    } label: {
                        Image(systemName: privacyLock.isPrivacyHidden ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(privacyLock.isPrivacyHidden ? .orange : .primary)
                    }
                    .accessibilityLabel(privacyLock.isPrivacyHidden ? "Reveal balances with Face ID or Passcode" : "Hide balances")

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
            .sheet(isPresented: $showingTransferSheet) {
                ProfileTransferSheet(store: store)
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
    @State private var paymentMode: PaymentMode = .upi
    @State private var txDate: Date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    Text("Adding to: \(store.activeProfileName)")
                        .font(.subheadline.bold())
                }

                Section("Type & Payment Mode") {
                    Picker("Type", selection: $type) {
                        ForEach(TxType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { newType in
                        category = newType == .income ? .salary : .food
                    }

                    Picker("Payment Mode", selection: $paymentMode) {
                        ForEach(PaymentMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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
                    DatePicker("Date & Time", selection: $txDate)
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
                            store.addTransaction(
                                title: title,
                                amount: val,
                                type: type,
                                category: category,
                                paymentMode: paymentMode,
                                date: txDate,
                                note: note
                            )
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
    @ObservedObject var privacyLock: PrivacyLockManager

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
                                    Text(displayINR(entry.total, hidden: privacyLock.isPrivacyHidden))
                                        .font(.subheadline.bold())
                                }
                                ProgressView(value: entry.total / maxVal)
                                    .tint(.blue)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section("Spending by Payment Mode") {
                    ForEach(PaymentMode.allCases) { mode in
                        let modeTotal = store.transactions
                            .filter { $0.type == .expense && $0.paymentMode == mode }
                            .reduce(0) { $0 + $1.amount }
                        HStack {
                            Label(mode.rawValue, systemImage: mode.icon)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(displayINR(modeTotal, hidden: privacyLock.isPrivacyHidden))
                                .font(.subheadline.bold())
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
    @ObservedObject var privacyLock: PrivacyLockManager

    @State private var budgetName: String = ""
    @State private var budgetLimitInput: String = ""
    @State private var selectedCategory: TxCategory? = nil

    // Recurring Bill inputs
    @State private var billTitle: String = ""
    @State private var billAmountInput: String = ""
    @State private var billCategory: TxCategory = .bills
    @State private var billPaymentMode: PaymentMode = .upi
    @State private var billFrequency: RecurrenceFrequency = .monthly
    @State private var billNextDue: Date = Date()
    @State private var billNote: String = ""

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

                Section("Add Recurring Bill (\(store.activeProfileName))") {
                    TextField("Bill name (e.g., Wi-Fi, Recharge, Tuition)", text: $billTitle)
                    TextField("Amount in ₹", text: $billAmountInput)
                        .keyboardType(.decimalPad)
                    Picker("Category", selection: $billCategory) {
                        ForEach(TxCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    Picker("Payment Mode", selection: $billPaymentMode) {
                        ForEach(PaymentMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Frequency", selection: $billFrequency) {
                        ForEach(RecurrenceFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    DatePicker("Next Due Date", selection: $billNextDue, displayedComponents: .date)
                    TextField("Optional note", text: $billNote)
                    Button("Save Recurring Bill") {
                        let cleaned = billAmountInput.replacingOccurrences(of: ",", with: "")
                        if let val = Double(cleaned), val > 0 {
                            store.addRecurringBill(
                                title: billTitle,
                                amount: val,
                                category: billCategory,
                                paymentMode: billPaymentMode,
                                frequency: billFrequency,
                                nextDueDate: billNextDue,
                                note: billNote
                            )
                            billTitle = ""
                            billAmountInput = ""
                            billNote = ""
                        }
                    }
                    .bold()
                }

                Section("Recurring Bills") {
                    if store.recurringBills.isEmpty {
                        Text("No recurring bills saved yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.recurringBills) { bill in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bill.title)
                                        .font(.headline)
                                    Text("\(bill.frequency.rawValue) • \(bill.paymentMode.rawValue) • Next: \(bill.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(displayINR(bill.amount, hidden: privacyLock.isPrivacyHidden))
                                    .font(.subheadline.bold())
                                Button("Log Now") {
                                    store.logRecurringBill(bill)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .onDelete(perform: store.deleteRecurringBills)
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
                                    Text("Limit: \(displayINR(budget.limitAmount, hidden: privacyLock.isPrivacyHidden))")
                                        .font(.subheadline.bold())
                                }
                                HStack {
                                    Text(budget.category?.rawValue ?? "All Expenses")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Spent: \(displayINR(spent, hidden: privacyLock.isPrivacyHidden))")
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
    @StateObject private var privacyLock = PrivacyLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LedgerHomeView(store: store, privacyLock: privacyLock)
                .tabItem {
                    Label("Ledger", systemImage: "indianrupeesign.circle")
                }

            BreakdownView(store: store, privacyLock: privacyLock)
                .tabItem {
                    Label("Breakdown", systemImage: "chart.bar.fill")
                }

            BudgetSettingsView(store: store, privacyLock: privacyLock)
                .tabItem {
                    Label("Budget", systemImage: "slider.horizontal.3")
                }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                privacyLock.lockIfNeeded()
            }
        }
        .onOpenURL { url in
            if let draft = RupaiyaDeepLink.parseQuickExpense(from: url) {
                store.quickExpenseDraft = draft
            }
        }
        .sheet(item: $store.quickExpenseDraft) { draft in
            QuickExpenseSheet(store: store, draft: draft)
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
