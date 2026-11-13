// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExpenseNotesCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ExpenseCore", targets: ["ExpenseCore"])],
    targets: [
        .target(name: "ExpenseCore", path: "ExpenseNotes", exclude: ["ExpenseNotesApp.swift", "ExpenseView.swift"],
                sources: ["Expense.swift", "ExpenseRepository.swift"]),
        .testTarget(name: "ExpenseCoreTests", dependencies: ["ExpenseCore"])
    ]
)
