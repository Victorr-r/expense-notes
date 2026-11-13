import XCTest
@testable import ExpenseCore

final class ExpenseCoreTests: XCTestCase {
    func testExactDecimalParsing() throws {
        XCTAssertEqual(try Money.parse(" 123,45 \n"), 12_345)
        XCTAssertEqual(try Money.parse("123.45"), 12_345)
        XCTAssertEqual(try Money.parse("0,01"), 1)
        XCTAssertEqual(try Money.parse("7.5"), 750)
        XCTAssertEqual(try Money.parse("10000000"), Money.maximum)
    }

    func testRejectsAmbiguousNegativeAndOverflowAmounts() {
        for text in ["", "0", "-1", "+1", ".50", "1.", "1,2.3", "1.234", "1 000", "1e3", "١", "10000000.01", "999999999999999999999999"] {
            XCTAssertThrowsError(try Money.parse(text), text)
        }
    }

    func testExpenseValidationAndTrimming() throws {
        let expense = try make(title: "  Кофе  ")
        XCTAssertEqual(expense.title, "Кофе")
        XCTAssertThrowsError(try make(title: " \n "))
        XCTAssertThrowsError(try make(title: String(repeating: "а", count: 81)))
        XCTAssertThrowsError(try make(kopecks: 0))
        XCTAssertThrowsError(try make(kopecks: Money.maximum + 1))
    }

    func testCategoryTotalsAreExactAndEmptyCategoriesOmitted() throws {
        let expenses = try [make(kopecks: 10, category: .food), make(kopecks: 20, category: .food), make(kopecks: 99, category: .home)]
        XCTAssertEqual(ExpenseSummary.total(expenses), 129)
        XCTAssertEqual(ExpenseSummary.categories(expenses), [CategoryTotal(category: .home, kopecks: 99), CategoryTotal(category: .food, kopecks: 30)])
        XCTAssertEqual(ExpenseSummary.total([]), 0)
        XCTAssertEqual(ExpenseSummary.categories([]), [])
    }

    func testMaximumTotalDoesNotOverflow() throws {
        let expenses = try (0..<ExpenseRepository.maximumCount).map { _ in try make(kopecks: Money.maximum) }
        try ExpenseRepository.validate(expenses)
        XCTAssertEqual(ExpenseSummary.total(expenses), 10_000_000_000_000)
        XCTAssertThrowsError(try ExpenseRepository.validate(expenses + [make()]))
    }

    func testMissingFileIsEmpty() throws {
        let (repository, folder) = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(try repository.load(), [])
    }

    func testRoundTripAndDeletionPersistAcrossRepositoryInstances() throws {
        let (repository, folder) = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try make(title: "Книга", kopecks: 12345, category: .leisure)
        let second = try make(title: "Метро", kopecks: 6500, category: .transport)
        try repository.save([first, second])
        let reopened = ExpenseRepository(url: repository.url)
        XCTAssertEqual(try reopened.load(), [first, second])
        try reopened.save([second])
        XCTAssertEqual(try repository.load(), [second])
        try reopened.save([])
        XCTAssertEqual(try repository.load(), [])
    }

    func testCorruptFileIsReportedAndNotModified() throws {
        let (repository, folder) = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bytes = Data("not valid JSON".utf8)
        try bytes.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.url), bytes)
    }

    func testInvalidDecodedMoneyAndUnknownVersionAreRejected() throws {
        let (repository, folder) = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: folder) }
        try repository.save([make()])
        let original = try Data(contentsOf: repository.url)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var records = try XCTUnwrap(json["expenses"] as? [[String: Any]])
        records[0]["kopecks"] = -100
        json["expenses"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["version"] = 42
        try JSONSerialization.data(withJSONObject: json).write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
    }

    func testDuplicateIdentityRejectedWithoutOverwritingExistingFile() throws {
        let (repository, folder) = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: folder) }
        let expense = try make()
        try repository.save([expense])
        XCTAssertThrowsError(try repository.save([expense, expense]))
        XCTAssertEqual(try repository.load(), [expense])
    }

    func testWriteFailureIsPropagated() throws {
        let (repository, folder) = temporaryRepository()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Make the intended parent directory a regular file.
        try Data("blocked".utf8).write(to: folder)
        XCTAssertThrowsError(try repository.save([make()]))
    }

    private func make(title: String = "Расход", kopecks: Int64 = 100, category: ExpenseCategory = .food) throws -> Expense {
        try Expense(title: title, kopecks: kopecks, category: category, date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func temporaryRepository() -> (ExpenseRepository, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ExpenseRepository(url: folder.appendingPathComponent("expenses.json")), folder)
    }
}
