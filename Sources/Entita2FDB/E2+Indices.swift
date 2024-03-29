import FDB
import LGNLog

public typealias E2FDBIndexedEntity = Entita2FDBIndexedEntity

/// A type erased key for indices. Used as a second protocol for enums
///
/// Usage is something like this:
/// ```
/// public enum IndexKey: String, AnyIndexKey {
///    case email, country
/// }
/// ```
///
/// And then just put it inside your `Entita2FDBIndexedEntity` declaration
public protocol AnyIndexKey: Hashable, RawRepresentable, CaseIterable where RawValue == String {}

public extension Entita2 {
    /// Represents an index
    class Index<M: Entita2FDBIndexedEntity> {
        internal let path: PartialKeyPath<M>
        internal let unique: Bool

        public init<V: FDBTuplePackable>(_ path: KeyPath<M, V>, unique: Bool) {
            self.path = path
            self.unique = unique
        }

        @usableFromInline internal func getTuplePackableValue(from instance: M) -> FDBTuplePackable? {
            return (instance[keyPath: self.path] as? FDBTuplePackable)
        }
    }
}

/// An extension of `Entita2FDBEntity` containing indices-related logic. Requires a `AnyIndexKey` type
/// (typealias or direct definition) and a static index scheme.
///
/// Example usage:
/// ```
/// final public class User: Entita2FDBIndexedEntity {
///     public enum IndexKey: String, AnyIndexKey {
///         case username, email, country, sex
///     }
///
///     public enum Sex: String, Codable, FDBTuplePackable {
///         case Male, Female
///
///         public func pack() -> Bytes {
///             self.rawValue.pack()
///         }
///     }
///
///     public let ID: Entita2.UUID
///
///     public var username: String
///     public var email: String
///     public var password: String
///     public var country: String
///     public var sex: Sex
///
///     public static var indices: [IndexKey: E2.Index<User>] = [
///         .username: E2.Index(\User.username, unique: true),
///         .email:    E2.Index(\User.email,    unique: true),
///         .country:  E2.Index(\User.country,  unique: false),
///         .sex:      E2.Index(\User.sex,      unique: false),
///     ]
///
///     // ...
///
///     public static func existsBy(username: String) async throws -> Bool {
///         try await User.existsByIndex(key: .username, value: username)
///     }
///
///     public static func loadBy(username: String) async throws -> User? {
///         try await User.loadByIndex(key: .username, value: username)
///     }
///
///     public static func loadAllBy(sex: Sex) async throws -> [User] {
///         try await User.loadAllByIndex(key: .sex, value: sex)
///     }
///
///     // ...
/// }
/// ```
public protocol Entita2FDBIndexedEntity: Entita2FDBEntity {
    associatedtype IndexKey: AnyIndexKey

    /// Index scheme
    static var indices: [IndexKey: E2.Index<Self>] { get }

    /// FDB subspace for storing indices
    static var indexSubspace: FDB.Subspace { get }

    /// FDB subspace for storing indices for indices
    var indexIndexSubspace: FDB.Subspace { get }

    /// Returns an FDB key for storing index data (_index for index_) for given `index`, `key` index name and index `value`
    func getIndexKeyForIndex(_ index: E2.Index<Self>, key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey

    /// Returns an FDB key for storing index for index data for given `index`, `key` index name and index `value`
    func getIndexIndexKeyForIndex(key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey

    /// Returns an FDB key for storing unique index data for given `key` index name and index `value`
    static func getIndexKeyForUniqueIndex(key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey

    /// Tries to load an entity for given unique index `key` and `value`. Optionally a `transaction` may be passed.
    static func loadByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within transaction: AnyFDBTransaction?
    ) async throws -> Self?

    /// Loads all entities for given non-unique index `key` and `value`.
    static func loadAllByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        limit: Int32,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool
    ) async throws -> [Self]

    /// Returns `Future<True>` if record exists for given index `key` name and `value`
    static func existsByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within transaction: AnyFDBTransaction?
    ) async throws -> Bool
}

public extension Entita2FDBIndexedEntity {
    static var indexSubspace: FDB.Subspace {
        Self.subspace["idx"][Self.entityName]
    }

    var indexIndexSubspace: FDB.Subspace {
        Self.indexSubspace["idx", self.getID()]
    }

    ///  current indexed property value for given `index`
    fileprivate func getIndexValueFrom(index: E2.Index<Self>) -> FDBTuplePackable? {
        index.getTuplePackableValue(from: self)
    }

    ///  a generalized subspace for given index `key` and `value`
    static func getGenericIndexSubspaceForIndex(key: IndexKey, value: FDBTuplePackable) -> FDB.Subspace {
        Self.indexSubspace[key.rawValue][value]
    }

    static func getIndexKeyForUniqueIndex(key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey {
        Self.getGenericIndexSubspaceForIndex(key: key, value: value)
    }

    func getIndexKeyForIndex(_ index: E2.Index<Self>, key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey {
        var result = Self.getGenericIndexSubspaceForIndex(key: key, value: value)

        if !index.unique {
            result = result[self.getID()]
        }

        return result
    }

    func getIndexIndexKeyForIndex(key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey {
        self.indexIndexSubspace[key.rawValue][value]
    }

    /// Creates (or overwrites) index for given `index` with `key` on optional `transaction`
    private func createIndex(
        key: IndexKey,
        index: E2.Index<Self>,
        within maybeTransaction: AnyFDBTransaction?
    ) async throws {
        guard let value = self.getIndexValueFrom(index: index) else {
            throw Entita2.E.IndexError(
                "Could not get tuple packable value for index '\(key)' in entity '\(Self.entityName)'"
            )
        }

        Logger.current.debug("Creating \(index.unique ? "unique " : "")index '\(key.rawValue)' with value '\(value)'")

        let transaction = try await Self.storage.unwrapAnyTransactionOrBegin(maybeTransaction)
        transaction.set(key: self.getIndexKeyForIndex(index, key: key, value: value), value: self.getIDAsKey())
        transaction.set(key: self.getIndexIndexKeyForIndex(key: key, value: value), value: [])
    }

    func afterInsert0(within transaction: AnyTransaction?) async throws {
        Logger.current.debug("Creating indices \(Self.indices.keys.map { $0.rawValue }) for entity '\(self.getID())'")

        for (key, index) in Self.indices {
            try await self.createIndex(
                key: key,
                index: index,
                within: transaction as? AnyFDBTransaction
            )
        }
    }

    func beforeDelete0(within tr: AnyTransaction?) async throws {
        let transaction = try await Self.storage.unwrapAnyTransactionOrBegin(tr as? AnyFDBTransaction)
        guard let entity = try await Self.load(by: self.getID(), within: transaction, snapshot: false) else {
            throw Entita2.E.IndexError(
                """
                Could not delete entity '\(Self.entityName)' : '\(self.getID())': \
                it might already be deleted
                """
            )
        }

        for (key, index) in Self.indices {
            guard let value = entity.getIndexValueFrom(index: index) else {
                continue
            }

            transaction.clear(key: self.getIndexKeyForIndex(index, key: key, value: value))
            transaction.clear(key: self.getIndexIndexKeyForIndex(key: key, value: value))
        }
    }

    /// Updates all indices (if updated) of current entity within an optional transaction
    fileprivate func updateIndices(within maybeTransaction: AnyFDBTransaction?) async throws {
        let transaction = try await Self.storage.unwrapAnyTransactionOrBegin(maybeTransaction)

        // todo task group
        for record in try await transaction.get(range: self.indexIndexSubspace.range).records {
            let indexFDBKey: FDB.Tuple

            do {
                indexFDBKey = try FDB.Tuple(from: record.key)
            } catch { continue }

            let tuples = indexFDBKey.tuple.compactMap { $0 }
            guard tuples.count >= 2 else {
                continue
            }
            let keyNameErased = tuples[tuples.count - 2]
            let indexValue = tuples[tuples.count - 1]

            guard let keyName = keyNameErased as? String else {
                throw Entita2.E.IndexError(
                    "Could not cast '\(keyNameErased)' as String in entity '\(Self.entityName)'"
                )
            }
            guard let key = IndexKey(rawValue: keyName) else {
                Logger.current.debug("Unknown index '\(keyName)' in entity '\(Self.entityName)', skipping")
                continue
            }
            guard let index = Self.indices[key] else {
                Logger.current.debug("No index '\(key)' in entity '\(Self.entityName)', skipping")
                continue
            }
            guard let propertyValue = self.getIndexValueFrom(index: index) else {
                throw Entita2.E.IndexError(
                    "Could not get property value for index '\(key)' in entity '\(Self.entityName)'"
                )
            }

            let probablyNewIndexKey = self.getIndexKeyForIndex(index, key: key, value: propertyValue)
            let previousIndexKey = self.getIndexKeyForIndex(index, key: key, value: indexValue)

            if previousIndexKey.asFDBKey() != probablyNewIndexKey.asFDBKey() {
                transaction.clear(key: previousIndexKey)
                transaction.clear(key: indexFDBKey)
            }
        }

        try await self.afterInsert0(within: transaction as? AnyTransaction)
    }

    func afterSave0(within transaction: AnyTransaction?) async throws {
        try await self.updateIndices(within: transaction as? AnyFDBTransaction)
    }

    /// Returns true if given index `key` is defined in indices schema
    private static func isValidIndex(key: IndexKey) -> Bool {
        guard let _ = Self.indices[key] else {
            let additionalInfo = "(available indices: \(Self.indices.keys.map { $0.rawValue }.joined(separator: ", ")))"
            Logger(label: "Entita2FDB")
                .error("Index '\(key)' not found in entity '\(Self.entityName)' \(additionalInfo)")
            return false
        }
        return true
    }

    static func loadAllByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        limit: Int32 = 0,
        within tr: AnyFDBTransaction? = nil,
        snapshot: Bool = false
    ) async throws -> [Self] {
        guard Self.isValidIndex(key: key) else {
            return []
        }

        let transaction = try await Self.storage.unwrapAnyTransactionOrBegin(tr)
        let results = try await transaction.get(
            range: Self.getGenericIndexSubspaceForIndex(key: key, value: value).range,
            limit: limit,
            snapshot: snapshot
        )

        var result: [Self] = []

        for record in results.records {
            if let value = try await Self.loadByRaw(IDBytes: record.value, within: transaction as? AnyTransaction) {
                result.append(value)
            }
        }

        return result
    }

    static func loadByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within maybeTransaction: AnyFDBTransaction? = nil
    ) async throws -> Self? {
        guard Self.isValidIndex(key: key) else {
            return nil
        }

        let transaction = try await Self.storage.unwrapAnyTransactionOrBegin(maybeTransaction)
        let maybeIDBytes = try await transaction.get(key: Self.getIndexKeyForUniqueIndex(key: key, value: value))
        guard let IDBytes = maybeIDBytes else {
            return nil
        }

        return try await Self.loadByRaw(
            IDBytes: IDBytes,
            within: transaction as? AnyTransaction
        )
    }

    static func existsByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within maybeTransaction: AnyFDBTransaction? = nil
    ) async throws -> Bool {
        guard Self.isValidIndex(key: key) else {
            return false
        }

        return try await Self.storage
            .unwrapAnyTransactionOrBegin(maybeTransaction)
            .get(key: Self.getIndexKeyForUniqueIndex(key: key, value: value)) != nil
    }
}
