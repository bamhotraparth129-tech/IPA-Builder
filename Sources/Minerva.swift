import SwiftUI

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

// MARK: - Store & CSV Export

final class LedgerStore: ObservableObject {
    @Published var transactions: [TransactionItem] = [] {
        didSet { save() }
    }
    @AppStorage("rupeeflow_monthly_budget") var monthlyBudget: Double = 10000

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("rupeeflow_transactions.json")
        load()
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
        guard amount > 0 else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = TransactionItem(
            title: cleanTitle.isEmpty ? category.rawValue : cleanTitle,
            amount: amount,
            type: type,
            category: category,
            date: Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        transactions.insert(item, at: 0)
    }

    func delete(at offsets: IndexSet) {
        transactions.remove(atOffsets: offsets)
    }

    func exportCSV() -> String {
        var rows = ["Date,Title,Type,Category,Amount_INR,Note"]
        let formatter = ISO8601DateFormatter()
        for t in transactions {
            let escapedTitle = t.title.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedNote = t.note.replacingOccurrences(of: "\"", with: "\"\"")
            rows.append("\"\(formatter.string(from: t.date))\",\"\(escapedTitle)\",\"\(t.type.rawValue)\",\"\(t.category.rawValue)\",\(String(format: "%.2f", t.amount)),\"\(escapedNote)\"")
        }
        return rows.joined(separator: "\n")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(transactions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TransactionItem].self, from: data) {
            self.transactions = decoded
        } else {
            self.transactions = [
                TransactionItem(title: "Monthly Allowance", amount: 12000, type: .income, category: .salary, note: "Starter entry"),
                TransactionItem(title: "Lunch & Chai", amount: 180, type: .expense, category: .food, note: "Sample expense")
            ]
        }
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

// MARK: - Views

struct LedgerHomeView: View {
    @ObservedObject var store: LedgerStore
    @State private var showingAddSheet = false

    private var budgetProgress: Double {
        guard store.monthlyBudget > 0 else { return 0 }
        return min(store.currentMonthExpenses / store.monthlyBudget, 1.5)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Net Balance")
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

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Monthly Budget")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(formatINR(store.currentMonthExpenses)) / \(formatINR(store.monthlyBudget))")
                                    .font(.caption.bold())
                            }
                            ProgressView(value: min(budgetProgress, 1.0))
                                .tint(budgetProgress > 1.0 ? .red : .green)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Recent Activity") {
                    if store.transactions.isEmpty {
                        Text("No entries yet. Tap + to record an expense or income.")
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
                Section("Spending by Category") {
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
    @State private var budgetInput: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly Expense Budget (₹)") {
                    TextField("Budget in ₹", text: $budgetInput)
                        .keyboardType(.decimalPad)
                    Button("Update Budget") {
                        let cleaned = budgetInput.replacingOccurrences(of: ",", with: "")
                        if let val = Double(cleaned), val > 0 {
                            store.monthlyBudget = val
                        }
                    }
                }

                Section("Export Data") {
                    ShareLink(item: store.exportCSV()) {
                        Label("Export Transactions CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Budget & Export")
            .onAppear {
                budgetInput = String(format: "%.0f", store.monthlyBudget)
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
