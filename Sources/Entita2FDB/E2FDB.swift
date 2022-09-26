import Entita2
import FDB

public protocol Entita2FDBEntity: Entita2Entity where Identifier: FDBTuplePackable, Storage: Entita2FDBStorage {
    /// Root application FDB Subspace — `/[root_subspace]`
    static var subspace: FDB.Subspace { get }
}

extension FDB.Transaction: Entita2Transaction {}
extension FDBTransaction where Self: Entita2Transaction {}

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

    /// Tries to load an entity for given ID within a given transaction (optional)
    @inlinable
    static func load(
        by ID: Identifier,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> Self? {
        let maybeBytes: Bytes? = try await Self.storage.load(
            by: Self.IDAsKey(ID: ID),
            within: transaction,
            snapshot: snapshot
        )
        
        return try await self.afterLoadRoutines0(
            maybeBytes: maybeBytes,
            within: transaction as? any Entita2Transaction
        )
    }

    /// Loads all entities in given subspace within a given transaction (optional)
    @inlinable
    static func loadAll(
        bySubspace subspace: FDB.Subspace,
        limit: Int32 = 0,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> [(ID: Self.Identifier, value: Self)] {
        let results = try await Self.storage.loadAll(
            by: subspace.range,
            limit: limit,
            within: transaction,
            snapshot: snapshot
        )

        return try results.records.map {
            let instance = try Self(from: $0.value)
            return (
                ID: instance.getID(),
                value: instance
            )
        }
    }

    /// Loads all entities in DB within a given transaction (optional)
    @inlinable
    static func loadAll(
        limit: Int32 = 0,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> [(ID: Self.Identifier, value: Self)] {
        try await Self.loadAll(
            bySubspace: Self.subspacePrefix,
            limit: limit,
            within: transaction,
            snapshot: snapshot
        )
    }

    /// Loads all entities for given key within a given transaction (optional)
    @inlinable
    static func loadAll(
        by key: any FDBKey,
        limit: Int32 = 0,
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> [(ID: Self.Identifier, value: Self)] {
        try await Self.loadAll(
            bySubspace: Self.subspacePrefix[key],
            limit: limit,
            within: transaction,
            snapshot: snapshot
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
        within transaction: (any FDBTransaction)? = nil,
        snapshot: Bool
    ) async throws -> FDB.KeyValuesResult {
        try await Self.storage.loadAll(
            by: Self.subspacePrefix.range,
            limit: limit,
            within: transaction,
            snapshot: snapshot
        )
    }

    /// Inserts current entity to DB within given transaction
    @inlinable
    func insert(within transaction: (any FDBTransaction)?, commit: Bool = true) async throws {
        try await self.insert(within: transaction as? any Entita2Transaction, commit: commit)
    }

    /// Saves current entity to DB within given transaction
    @inlinable
    func save(
        by ID: Identifier? = nil, within transaction: (any FDBTransaction)?, commit: Bool = true) async throws {
        try await self.save(by: ID, within: transaction as? any Entita2Transaction, commit: commit)
    }

    /// Deletes current entity from DB within given transaction
    @inlinable
    func delete(within transaction: (any FDBTransaction)?, commit: Bool = true) async throws {
        try await self.delete(within: transaction as? any Entita2Transaction, commit: commit)
    }
}
