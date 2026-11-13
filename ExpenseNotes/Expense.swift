import Foundation

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, transport, home, leisure, health, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: "Еда"
        case .transport: "Транспорт"
        case .home: "Дом"
        case .leisure: "Досуг"
        case .health: "Здоровье"
        case .other: "Другое"
        }
    }
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .transport: "tram.fill"
        case .home: "house.fill"
        case .leisure: "sparkles"
        case .health: "heart.fill"
        case .other: "ellipsis"
        }
    }
}

enum ExpenseError: LocalizedError, Equatable {
    case invalidAmount, invalidNote, limitReached, invalidFile
    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Введите сумму от 0,01 до 10 000 000 ₽, не более двух знаков после запятой."
        case .invalidNote: "Название расхода должно содержать от 1 до 80 символов."
        case .limitReached: "Достигнут предел: 10 000 записей. Удалите ненужные расходы."
        case .invalidFile: "Не удалось прочитать сохранённые расходы. Файл оставлен без изменений."
        }
    }
}

/// Money is stored as integer kopecks; input never passes through Double.
enum Money {
    static let maximum: Int64 = 1_000_000_000

    static func parse(_ text: String) throws -> Int64 {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), !pieces[0].isEmpty,
              pieces.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              pieces[0].count <= 8,
              let whole = Int64(pieces[0]) else { throw ExpenseError.invalidAmount }
        var fraction: Int64 = 0
        if pieces.count == 2 {
            guard (1...2).contains(pieces[1].count), let digits = Int64(pieces[1]) else {
                throw ExpenseError.invalidAmount
            }
            fraction = pieces[1].count == 1 ? digits * 10 : digits
        }
        let result = whole * 100 + fraction
        guard (1...maximum).contains(result) else { throw ExpenseError.invalidAmount }
        return result
    }

    static func formatted(_ kopecks: Int64) -> String {
        let value = Decimal(kopecks) / 100
        return value.formatted(.currency(code: "RUB").locale(Locale(identifier: "ru_RU")))
    }
}

struct Expense: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let kopecks: Int64
    let category: ExpenseCategory
    let date: Date

    init(id: UUID = UUID(), title: String, kopecks: Int64, category: ExpenseCategory, date: Date) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count) else { throw ExpenseError.invalidNote }
        guard (1...Money.maximum).contains(kopecks) else { throw ExpenseError.invalidAmount }
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw ExpenseError.invalidFile }
        self.id = id
        self.title = trimmed
        self.kopecks = kopecks
        self.category = category
        self.date = date
    }

    func validate() throws {
        _ = try Expense(id: id, title: title, kopecks: kopecks, category: category, date: date)
    }
}

struct CategoryTotal: Identifiable, Equatable {
    let category: ExpenseCategory
    let kopecks: Int64
    var id: ExpenseCategory { category }
}

enum ExpenseSummary {
    /// Repository validation bounds the total to 10,000 × 1,000,000,000 kopecks.
    static func total(_ expenses: [Expense]) -> Int64 {
        expenses.reduce(0) { $0 + $1.kopecks }
    }

    static func categories(_ expenses: [Expense]) -> [CategoryTotal] {
        ExpenseCategory.allCases.compactMap { category in
            let sum = total(expenses.filter { $0.category == category })
            return sum > 0 ? CategoryTotal(category: category, kopecks: sum) : nil
        }.sorted { left, right in
            left.kopecks == right.kopecks
                ? left.category.rawValue < right.category.rawValue
                : left.kopecks > right.kopecks
        }
    }
}
