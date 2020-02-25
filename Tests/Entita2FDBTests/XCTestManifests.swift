import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(Entita2FDBTests.allTests),
    ]
}
#endif
