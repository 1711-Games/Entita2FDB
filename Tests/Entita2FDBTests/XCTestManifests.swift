import XCTest

#if !canImport(ObjectiveC)

extension Entita2FDBTests {
    static let __allTests__Entita2FDBTests = [
        ("testGeneric", asyncTest(testGeneric)),
        ("test_loadAllByIndex_loadAll", asyncTest(test_loadAllByIndex_loadAll)),
        ("testLoadWithTransaction", asyncTest(testLoadWithTransaction)),
        ("testExistsByIndex", asyncTest(testExistsByIndex)),
        ("testInvalidIndex", asyncTest(testInvalidIndex)),
        ("testDoesRelateToThis", testDoesRelateToThis),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(Entita2FDBTests.__allTests__Entita2FDBTests),
    ]
}
#endif
