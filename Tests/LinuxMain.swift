import XCTest
import Entita2FDBTests

@main public struct Main {
    public static func main() {
        var tests = [XCTestCaseEntry]()
        tests += Entita2FDBTests.__allTests()
        XCTMain(tests)
    }
}
