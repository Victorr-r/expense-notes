import Foundation

/// Atomic, versioned JSON. A failed load is never silently replaced by an empty list.
struct ExpenseRepository {
    let url: URL
    static let maximumCount = 10_000
    private struct Document: Codable {
        let version: Int
        let expenses: [Expense]
    }

    static func applicationRepository() throws -> ExpenseRepository {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true)
            .appendingPathComponent("ExpenseNotes", isDirectory: true)
        return ExpenseRepository(url: folder.appendingPathComponent("expenses.json"))
    }

    func load() throws -> [Expense] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw ExpenseError.invalidFile }
        guard document.version == 1 else { throw ExpenseError.invalidFile }
        try Self.validate(document.expenses)
        return document.expenses
    }

    func save(_ expenses: [Expense]) throws {
        try Self.validate(expenses)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(version: 1, expenses: expenses))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func validate(_ expenses: [Expense]) throws {
        guard expenses.count <= maximumCount else { throw ExpenseError.limitReached }
        guard Set(expenses.map(\.id)).count == expenses.count else { throw ExpenseError.invalidFile }
        for expense in expenses { try expense.validate() }
    }
}
