import SwiftUI
import Charts

@MainActor
final class ExpenseStore: ObservableObject {
    @Published private(set) var expenses: [Expense] = []
    @Published private(set) var loaded = false
    @Published var error: String?
    private var repository: ExpenseRepository?
    let demo: Bool

    init() {
        #if DEBUG
        demo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        demo = false
        #endif
        reload()
    }

    func reload() {
        do {
            if demo {
                expenses = try Self.examples()
            } else {
                let source = try ExpenseRepository.applicationRepository()
                expenses = try source.load()
                repository = source
            }
            loaded = true
            error = nil
        } catch {
            loaded = false
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func add(title: String, amount: String, category: ExpenseCategory, date: Date) -> Bool {
        do {
            let expense = try Expense(title: title, kopecks: Money.parse(amount), category: category, date: date)
            return commit(expenses + [expense])
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func remove(_ ids: Set<UUID>) { _ = commit(expenses.filter { !ids.contains($0.id) }) }

    private func commit(_ updated: [Expense]) -> Bool {
        guard loaded else { return false }
        do {
            try ExpenseRepository.validate(updated)
            if !demo {
                guard let repository else { throw ExpenseError.invalidFile }
                try repository.save(updated)
            }
            // Publish the change only after successful persistence.
            expenses = updated
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private static func examples() throws -> [Expense] {
        try [
            ("Продукты на неделю", "2840.50", ExpenseCategory.food, 0),
            ("Кофе по дороге", "260", .food, 0),
            ("Проездной", "1700", .transport, 1),
            ("Билеты в кино", "1200", .leisure, 2),
            ("Для уютного дома", "890.90", .home, 3)
        ].map { item in
            try Expense(title: item.0, kopecks: Money.parse(item.1), category: item.2,
                        date: Calendar.current.date(byAdding: .day, value: -item.3, to: .now) ?? .now)
        }
    }
}

private extension ExpenseCategory {
    var color: Color {
        switch self {
        case .food: Color(red: 0.10, green: 0.47, blue: 0.41)
        case .transport: Color(red: 0.28, green: 0.44, blue: 0.72)
        case .home: Color(red: 0.75, green: 0.48, blue: 0.20)
        case .leisure: Color(red: 0.59, green: 0.36, blue: 0.68)
        case .health: Color(red: 0.76, green: 0.32, blue: 0.38)
        case .other: .gray
        }
    }
}

struct ExpenseView: View {
    @StateObject private var store = ExpenseStore()
    @State private var showingAdd = false
    @State private var currentMonth = true
    private var visible: [Expense] {
        store.expenses.filter { !currentMonth || Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
    private var totals: [CategoryTotal] { ExpenseSummary.categories(visible) }

    var body: some View {
        NavigationStack {
            Group {
                if !store.loaded {
                    ContentUnavailableView {
                        Label("Данные недоступны", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Сохранённый файл не изменён. Попробуйте прочитать его ещё раз.")
                    } actions: {
                        Button("Повторить") { store.reload() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    expenseList
                }
            }
            .navigationTitle("Мои расходы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Добавить расход")
                    .disabled(!store.loaded)
                }
            }
            .sheet(isPresented: $showingAdd) { AddExpenseView(store: store) }
            .alert("Не удалось выполнить действие", isPresented: Binding(
                get: { store.error != nil && !showingAdd },
                set: { if !$0 { store.error = nil } }
            )) {
                Button("Понятно") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
        .tint(Color(red: 0.10, green: 0.47, blue: 0.41))
    }

    private var expenseList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(currentMonth ? "В ЭТОМ МЕСЯЦЕ" : "ЗА ВСЁ ВРЕМЯ", systemImage: "chart.bar.xaxis")
                            .font(.caption.weight(.semibold)).tracking(1)
                        Spacer()
                        if store.demo { Text("ДЕМО").font(.caption2.bold()) }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    Text(Money.formatted(ExpenseSummary.total(visible)))
                        .font(.system(size: 35, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
                    Text("Записей: \(visible.count) · Всё под контролем")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.10, green: 0.23, blue: 0.22), in: RoundedRectangle(cornerRadius: 24))
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                Picker("Период", selection: $currentMonth) {
                    Text("Этот месяц").tag(true)
                    Text("Всё время").tag(false)
                }.pickerStyle(.segmented)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if visible.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(currentMonth && !store.expenses.isEmpty ? "Месяц без расходов" : "Начнём с первого расхода", systemImage: "wallet.bifold")
                    } description: {
                        Text("Добавляйте покупки, чтобы видеть, куда уходят деньги. Все записи хранятся на устройстве.")
                    } actions: {
                        Button("Добавить расход") { showingAdd = true }.buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("По категориям") {
                    Chart(totals) { item in
                        BarMark(x: .value("Рубли", Double(item.kopecks) / 100),
                                y: .value("Категория", item.category.title))
                            .foregroundStyle(item.category.color).cornerRadius(5)
                            .accessibilityLabel(item.category.title)
                            .accessibilityValue(Money.formatted(item.kopecks))
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(totals.count) * 36 + 10)
                    .padding(.vertical, 8)
                    ForEach(totals) { item in
                        HStack {
                            Circle().fill(item.category.color).frame(width: 8, height: 8)
                            Text(item.category.title)
                            Spacer()
                            Text(Money.formatted(item.kopecks)).fontWeight(.medium)
                        }.font(.subheadline)
                    }
                }
                Section {
                    ForEach(visible) { expense in
                        HStack(spacing: 13) {
                            Image(systemName: expense.category.symbol)
                                .frame(width: 40, height: 40)
                                .foregroundStyle(expense.category.color)
                                .background(expense.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(expense.title).font(.body.weight(.medium))
                                Text("\(expense.category.title) · \(expense.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU"))))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(Money.formatted(expense.kopecks))
                                .font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                        }.padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in store.remove(Set(offsets.map { visible[$0].id })) }
                } header: { Text("История расходов") }
                footer: { Text("Смахните запись влево, чтобы удалить её.\(store.demo ? " Демо-режим: изменения не сохраняются." : "")") }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct AddExpenseView: View {
    @ObservedObject var store: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount = ""
    @State private var category: ExpenseCategory = .food
    @State private var date = Date.now
    @FocusState private var focused: Bool
    private var valid: Bool {
        (1...80).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) && (try? Money.parse(amount)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Покупка") {
                    TextField("Например, продукты", text: $title).focused($focused)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Название расхода")
                    HStack {
                        TextField("0,00", text: $amount).keyboardType(.decimalPad)
                            .accessibilityLabel("Сумма в рублях")
                        Text("₽").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Категория", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    DatePicker("Дата", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                } footer: {
                    Text("Сумма от 0,01 до 10 000 000 ₽. Разделитель — точка или запятая. Название — до 80 символов.")
                }
            }
            .navigationTitle("Новый расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        if store.add(title: title, amount: amount, category: category, date: date) { dismiss() }
                    }.fontWeight(.semibold).disabled(!valid)
                }
            }
            .alert("Не удалось сохранить", isPresented: Binding(
                get: { store.error != nil }, set: { if !$0 { store.error = nil } }
            )) { Button("Понятно") { store.error = nil } } message: { Text(store.error ?? "") }
        }
    }
}
