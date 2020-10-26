import Entita2
import FDB
import NIO

public protocol Entita2FDBEntity: Entita2Entity where Identifier: FDBTuplePackable, Storage: Entita2FDBStorage {
    /// Root application FDB Subspace — `/[root_subspace]`
    static var subspace: FDB.Subspace { get }
}

extension FDB.Transaction: AnyTransaction {}
extension AnyFDBTransaction where Self: AnyTransaction {}

public typealias E2FDBEntity = Entita2FDBEntity

public extension Entita2FDBEntity {
    @inlinable
    static func IDBytesAsKey(bytes: Bytes) -> Bytes {
        Self.subspacePrefix[bytes].asFDBKey()
    }

    @inlinable
    static func IDAsKey(ID: Identifier) -> Bytes {
        Self.subspacePrefix[ID].asFDBKey()
    }

    static func doesRelateToThis(tuple: FDB.Tuple) -> Bool {
        let flat = tuple.tuple.compactMap { $0 }
        guard flat.count >= 2 else {
            return false
        }
        guard let value = flat[flat.count - 2] as? String, value == self.entityName else {
            return false
        }
        return true
    }

    @inlinable
    func getIDAsKey() -> Bytes {
        Self.IDAsKey(ID: self.getID())
    }

    /// Current entity-related FDB Subspace — `/[root_subspace]/[entity_name]`
    static var subspacePrefix: FDB.Subspace {
        self.subspace[self.entityName]
    }

    /// Tries to load an entity for given ID within a newly started transaction
    @inlinable
    static func loadWithTransaction(
        by ID: Identifier,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<(Self?, AnyFDBTransaction)> {
        Self.storage.withTransaction(on: eventLoop) { transaction in
            Self
                .load(by: ID, within: transaction, snapshot: snapshot, on: eventLoop)
                .map { ($0, transaction) }
        }
    }

    /// Tries to load an entity for given ID within a given transaction (optional)
    @inlinable
    static func load(
        by ID: Identifier,
        within transaction: AnyFDBTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Self?> {
        Self.storage
            .load(
                by: Self.IDAsKey(ID: ID),
                within: transaction,
                snapshot: snapshot,
                on: eventLoop
            )
            .flatMap { (maybeBytes: Bytes?) -> EventLoopFuture<Self?> in
                self.afterLoadRoutines0(
                    maybeBytes: maybeBytes,
                    within: transaction as? AnyTransaction,
                    on: eventLoop
                )
            }
    }

    /// Loads all entities in given subspace within a given transaction (optional)
    @inlinable
    static func loadAll(
        bySubspace subspace: FDB.Subspace,
        limit: Int32 = 0,
        within transaction: AnyFDBTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<[(ID: Self.Identifier, value: Self)]> {
        Self.storage.loadAll(
            by: subspace.range,
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        ).flatMapThrowing { results in
            try results.records.map {
                let instance = try Self(from: $0.value)
                return (
                    ID: instance.getID(),
                    value: instance
                )
            }
        }
    }

    /// Loads all entities in DB within a given transaction (optional)
    @inlinable
    static func loadAll(
        limit: Int32 = 0,
        within transaction: AnyFDBTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<[(ID: Self.Identifier, value: Self)]> {
        Self.loadAll(
            bySubspace: Self.subspacePrefix,
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        )
    }

    /// Loads all entities for given key within a given transaction (optional)
    @inlinable
    static func loadAll(
        by key: AnyFDBKey,
        limit: Int32 = 0,
        within transaction: AnyFDBTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<[(ID: Self.Identifier, value: Self)]> {
        Self.loadAll(
            bySubspace: Self.subspacePrefix[key],
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        )
    }

    /// Loads all records from DB withing a given transaction (optional)
    ///
    /// Useful for migrations
    @inlinable
    static func loadAllRaw(
        limit: Int32 = 0,
        mode _: FDB.StreamingMode = .wantAll,
        iteration _: Int32 = 1,
        within transaction: AnyFDBTransaction? = nil,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
        Self.storage.loadAll(
            by: Self.subspacePrefix.range,
            limit: limit,
            within: transaction,
            snapshot: snapshot,
            on: eventLoop
        )
    }

    /// Inserts current entity to DB within given transaction
    @inlinable
    func insert(
        within transaction: AnyFDBTransaction?,
        commit: Bool = true,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        self.insert(within: transaction as? AnyTransaction, commit: commit, on: eventLoop)
    }

    /// Saves current entity to DB within given transaction
    @inlinable
    func save(
        by ID: Identifier? = nil,
        within transaction: AnyFDBTransaction?,
        commit: Bool = true,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        self.save(by: ID, within: transaction as? AnyTransaction, commit: commit, on: eventLoop)
    }

    /// Deletes current entity from DB within given transaction
    @inlinable
    func delete(
        within transaction: AnyFDBTransaction?,
        commit: Bool = true,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        self.delete(within: transaction as? AnyTransaction, commit: commit, on: eventLoop)
    }
}
