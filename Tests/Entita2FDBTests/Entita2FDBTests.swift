import Foundation
import XCTest
import LGNCore
import NIO
import FDB
import MessagePack
import Entita2
@testable import Entita2FDB

final class Entita2FDBTests: XCTestCase {
    struct TestEntity: E2FDBIndexedEntity, Equatable {
        typealias Identifier = E2.UUID

        public enum IndexKey: String, AnyIndexKey {
            case email, country, invalidIndex
        }

        static var storage: some E2FDBStorage = Entita2FDBTests.fdb
        static var subspace: FDB.Subspace = Entita2FDBTests.subspace
        static var format: E2.Format = .JSON
        static var IDKey: KeyPath<Self, Identifier> = \.ID

        static var indices: [IndexKey: E2.Index<Self>] = [
            .email: E2.Index(\.email, unique: true),
            .country: E2.Index(\.country, unique: false),
        ]

        let ID: Identifier
        var email: String
        var country: String
    }

    static var fdb: FDB!
    static var subspace: FDB.Subspace!
    static var eventLoopGroup: EventLoopGroup!
    static var eventLoop: EventLoop {
        self.eventLoopGroup.next()
    }

    var semaphore: DispatchSemaphore {
        return DispatchSemaphore(value: 0)
    }

    let email1 = "foo"
    let email2 = "bar"
    let email3 = "baz"
    let email4 = "sas"

    override class func setUp() {
        super.setUp()
        var logger = Logger(label: "testlogger")
        logger.logLevel = .debug
        FDB.logger = logger
        E2.logger = logger
        self.fdb = FDB()
        self.subspace = FDB.Subspace("test \(Int.random(in: 0 ..< Int.max))")
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override class func tearDown() {
        super.tearDown()
        FDB.logger.notice("Cleanup")
        do {
            try self.fdb.clear(subspace: self.subspace)
        } catch {
            XCTFail("Could not tearDown: \(error)")
        }
        self.fdb.disconnect()
        self.fdb = nil
        try! self.eventLoopGroup.syncShutdownGracefully()
    }

    func testGeneric() throws {
        let id1 = E2.UUID()
        var instance1 = TestEntity(
            ID: id1,
            email: "jennie.pink@mephone.org.uk",
            country: "UK"
        )

        XCTAssertNoThrow(
            try TestEntity
                .begin(on: Self.eventLoop)
                .flatMap { (transaction: AnyTransaction?) -> Future<Void> in
                    return instance1.insert(commit: true, within: transaction, on: Self.eventLoop)
                }
                .wait()
        )
        XCTAssertEqual(instance1, try TestEntity.load(by: id1, on: Self.eventLoop).wait())
        XCTAssertEqual(
            instance1,
            try TestEntity.loadByIndex(key: .email, value: "jennie.pink@mephone.org.uk", on: Self.eventLoop).wait()
        )

        instance1.email = "bender@ilovebender.com"
        XCTAssertNoThrow(try instance1.save(on: Self.eventLoop).wait())
        XCTAssertEqual(
            instance1,
            try TestEntity.loadByIndex(key: .email, value: "bender@ilovebender.com", on: Self.eventLoop).wait()
        )

        try instance1.delete(on: Self.eventLoop).wait()
    }

    func test_loadAllByIndex_loadAll() throws {
        let uuid1 = E2.UUID("AAAAAAAA-F0AB-4782-9267-B52CF61B7E1A")!
        let uuid2 = E2.UUID("BBBBBBBB-F0AB-4782-9267-B52CF61B7E1A")!
        let uuid3 = E2.UUID("CCCCCCCC-F0AB-4782-9267-B52CF61B7E1A")!
        let uuid4 = E2.UUID("DDDDDDDD-F0AB-4782-9267-B52CF61B7E1A")!
        let instance1 = TestEntity(ID: uuid1, email: self.email1, country: "RU")
        let instance2 = TestEntity(ID: uuid2, email: self.email2, country: "RU")
        let instance3 = TestEntity(ID: uuid3, email: self.email3, country: "UA")
        let instance4 = TestEntity(ID: uuid4, email: self.email4, country: "KE")

        XCTAssertNoThrow(
            try Future.andAllSucceed(
                [
                    instance1.insert(on: Self.eventLoop),
                    instance2.insert(on: Self.eventLoop),
                    instance3.insert(on: Self.eventLoop),
                    instance4.insert(on: Self.eventLoop),
                ],
                on: Self.eventLoop
            ).wait()
        )

        func load1() throws -> [(ID: TestEntity.Identifier, value: TestEntity)] {
            return try TestEntity
                .loadAll(
                    bySubspace: Self.subspace[TestEntity.entityName],
                    snapshot: true,
                    on: Self.eventLoop)
                .wait()
        }

        XCTAssertNoThrow(try load1())
        let result1 = try load1()
        XCTAssertEqual(
            [instance1, instance2, instance3, instance4],
            result1.map { $0.value }
        )
        XCTAssertEqual(
            [instance1.ID, instance2.ID, instance3.ID, instance4.ID],
            result1.map { $0.ID }
        )

        func load2() throws -> [(ID: TestEntity.Identifier, value: TestEntity)] {
            return try TestEntity.loadAll(snapshot: true, on: Self.eventLoop).wait()
        }

        XCTAssertNoThrow(try load2())
        let result2 = try load2()
        XCTAssertEqual(
            [instance1, instance2, instance3, instance4],
            result2.map { $0.value }
        )
        XCTAssertEqual(
            [instance1.ID, instance2.ID, instance3.ID, instance4.ID],
            result2.map { $0.ID }
        )

        XCTAssertEqual(
            [instance1, instance2],
            try TestEntity.loadAllByIndex(key: .country, value: "RU", on: Self.eventLoop).wait()
        )

        var instance4_1 = try TestEntity.loadByIndex(key: .email, value: self.email4, on: Self.eventLoop).wait()
        XCTAssertNotNil(instance4_1)
        instance4_1!.email = "kek"
        try instance4_1!.save(on: Self.eventLoop).wait()

        /// Ensure that subspace is empty after deletion
        XCTAssertNotEqual(0, try Self.fdb.get(range: Self.subspace.range).records.count)

        try instance1.delete(on: Self.eventLoop).wait()
        try instance2.delete(on: Self.eventLoop).wait()
        try instance3.delete(on: Self.eventLoop).wait()
        try instance4.delete(on: Self.eventLoop).wait()

        XCTAssertEqual(0, try Self.fdb.get(range: Self.subspace.range).records.count)
    }

    func testLoadWithTransaction() throws {
        enum E: Error {
            case err
        }
        let instance1 = TestEntity(ID: .init(), email: "foo", country: "UA")
        XCTAssertNoThrow(try instance1.save(on: Self.eventLoop).wait())
        XCTAssertEqual(
            instance1,
            try TestEntity
                .loadWithTransaction(by: instance1.ID, snapshot: false, on: Self.eventLoop)
                .flatMapThrowing { maybeEntity, transaction in
                    guard let entity = maybeEntity else {
                        throw E.err
                    }
                    return (entity, transaction)
                }
                .flatMap { (entity: TestEntity, transaction: AnyFDBTransaction) -> Future<TestEntity?> in
                    entity
                        .delete(commit: false, within: transaction as? AnyTransaction, on: Self.eventLoop)
                        .flatMap {
                            transaction.reset()

                            return TestEntity.load(
                                by: instance1.ID,
                                within: transaction,
                                snapshot: false,
                                on: Self.eventLoop
                            )
                        }
                }
                .wait()
        )
    }

    func testExistsByIndex() throws {
        let email = "foo@bar.baz"
        XCTAssertFalse(try TestEntity.existsByIndex(key: .email, value: email, on: Self.eventLoop).wait())
        try TestEntity(ID: .init(), email: email, country: "RU").save(on: Self.eventLoop).wait()
        XCTAssertTrue(try TestEntity.existsByIndex(key: .email, value: email, on: Self.eventLoop).wait())
        let instance = try TestEntity.loadByIndex(key: .email, value: email, on: Self.eventLoop).wait()
        XCTAssertNotNil(instance)
        try instance!.delete(on: Self.eventLoop).wait()
        XCTAssertFalse(try TestEntity.existsByIndex(key: .email, value: email, on: Self.eventLoop).wait())
    }

    func testInvalidIndex() throws {
        XCTAssertEqual(false, try TestEntity.existsByIndex(key: .invalidIndex, value: "lul", on: Self.eventLoop).wait())
        XCTAssertEqual([], try TestEntity.loadAllByIndex(key: .invalidIndex, value: "lul", on: Self.eventLoop).wait())
        XCTAssertEqual(nil, try TestEntity.loadByIndex(key: .invalidIndex, value: "lul", on: Self.eventLoop).wait())
        XCTAssertEqual(nil, try TestEntity.loadByIndex(key: .email, value: "lul", on: Self.eventLoop).wait())
    }

    func testDoesRelateToThis() throws {
        let instance = TestEntity(ID: .init(), email: "foo", country: "UA")
        let key = instance.getIDAsKey()
        let tuple = try FDB.Tuple(from: key)
        XCTAssertTrue(TestEntity.doesRelateToThis(tuple: tuple))
        XCTAssertFalse(TestEntity.doesRelateToThis(tuple: FDB.Tuple("foo", "bar")))
        XCTAssertFalse(TestEntity.doesRelateToThis(tuple: FDB.Tuple("foo")))
        XCTAssertFalse(TestEntity.doesRelateToThis(tuple: FDB.Tuple()))
    }

    static var allTests = [
        ("testGeneric", testGeneric),
        ("test_loadAllByIndex_loadAll", test_loadAllByIndex_loadAll),
        ("testLoadWithTransaction", testLoadWithTransaction),
        ("testExistsByIndex", testExistsByIndex),
        ("testInvalidIndex", testInvalidIndex),
        ("testDoesRelateToThis", testDoesRelateToThis),
    ]
}
