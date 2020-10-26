import NIO
import FDB
import Logging

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
///     public static func existsBy(
///         username: String,
///         on eventLoop: EventLoop
///     ) -> EventLoopFuture<Bool> {
///         User.existsByIndex(
///             key: .username,
///             value: username,
///             on: eventLoop
///         )
///     }
///
///     public static func loadBy(
///         username: String,
///         on eventLoop: EventLoop
///     ) -> EventLoopFuture<User?> {
///         User.loadByIndex(
///             key: .username,
///             value: username,
///             on: eventLoop
///         )
///     }
///
///     public static func loadAllBy(
///         sex: Sex,
///         on eventLoop: EventLoop
///     ) -> EventLoopFuture<[User]> {
///         User.loadAllByIndex(
///             key: .sex,
///             value: sex,
///             on: eventLoop
///         )
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
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Self?>

    /// Loads all entities for given non-unique index `key` and `value`.
    static func loadAllByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        limit: Int32,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<[Self]>

    /// Returns `Future<True>` if record exists for given index `key` name and `value`
    static func existsByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Bool>
}

public extension Entita2FDBIndexedEntity {
    static var indexSubspace: FDB.Subspace {
        return Self.subspace["idx"][Self.entityName]
    }

    var indexIndexSubspace: FDB.Subspace {
        return Self.indexSubspace["idx", self.getID()]
    }

    /// Returns current indexed property value for given `index`
    fileprivate func getIndexValueFrom(index: E2.Index<Self>) -> FDBTuplePackable? {
        return index.getTuplePackableValue(from: self)
    }

    /// Returns a generalized subspace for given index `key` and `value`
    static func getGenericIndexSubspaceForIndex(
        key: IndexKey,
        value: FDBTuplePackable
    ) -> FDB.Subspace {
        return Self.indexSubspace[key.rawValue][value]
    }

    static func getIndexKeyForUniqueIndex(
        key: IndexKey,
        value: FDBTuplePackable
    ) -> AnyFDBKey {
        return Self.getGenericIndexSubspaceForIndex(key: key, value: value)
    }

    func getIndexKeyForIndex(
        _ index: E2.Index<Self>,
        key: IndexKey,
        value: FDBTuplePackable
    ) -> AnyFDBKey {
        var result = Self.getGenericIndexSubspaceForIndex(key: key, value: value)

        if !index.unique {
            result = result[self.getID()]
        }

        return result
    }

    func getIndexIndexKeyForIndex(key: IndexKey, value: FDBTuplePackable) -> AnyFDBKey {
        return self.indexIndexSubspace[key.rawValue][value]
    }

    /// Creates (or overwrites) index for given `index` with `key` on optional `transaction`
    private func createIndex(
        key: IndexKey,
        index: E2.Index<Self>,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        guard let value = self.getIndexValueFrom(index: index) else {
            return eventLoop.makeFailedFuture(
                Entita2.E.IndexError(
                    "Could not get tuple packable value for index '\(key)' in entity '\(Self.entityName)'"
                )
            )
        }

        Entita2.logger.debug("Creating \(index.unique ? "unique " : "")index '\(key.rawValue)' with value '\(value)'")

        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.set(key: self.getIndexKeyForIndex(index, key: key, value: value), value: self.getIDAsKey()) }
            .flatMap { $0.set(key: self.getIndexIndexKeyForIndex(key: key, value: value), value: []) }
            .map { _ in () }
    }

    func afterInsert0(
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        Entita2.logger.debug("Creating indices \(Self.indices.keys.map { $0.rawValue }) for entity '\(self.getID())'")

        return EventLoopFuture<Void>.andAllSucceed(
            Self.indices.map {
                self.createIndex(
                    key: $0.key,
                    index: $0.value,
                    within: transaction as? AnyFDBTransaction,
                    on: eventLoop
                )
            },
            on: eventLoop
        )
    }

    func beforeDelete0(within tr: AnyTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        Self.storage
            .unwrapAnyTransactionOrBegin(tr as? AnyFDBTransaction, on: eventLoop)
            .flatMap { (transaction: AnyFDBTransaction) -> EventLoopFuture<Void> in
                Self
                    .load(by: self.getID(), within: transaction, snapshot: false, on: eventLoop)
                    .flatMapThrowing { maybeEntity in
                        guard let entity = maybeEntity else {
                            throw Entita2.E.IndexError(
                                """
                                Could not delete entity '\(Self.entityName)' : '\(self.getID())': \
                                it might already be deleted
                                """
                            )
                        }
                        return entity
                    }
                    .flatMap { (entity: Self) in
                        EventLoopFuture<Void>.andAllSucceed(
                            Self.indices.map { key, index in
                                guard let value = entity.getIndexValueFrom(index: index) else {
                                    return eventLoop.makeSucceededFuture()
                                }
                                return eventLoop.makeSucceededFuture()
                                    .flatMap { _ in
                                        transaction.clear(key: self.getIndexKeyForIndex(index, key: key, value: value))
                                    }
                                    .flatMap { _ in
                                        transaction.clear(key: self.getIndexIndexKeyForIndex(key: key, value: value))
                                    }
                                    .map { _ in () }
                            },
                            on: eventLoop
                        )
                    }
            }
    }

    /// Updates all indices (if updated) of current entity within an optional transaction
    fileprivate func updateIndices(
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.get(range: self.indexIndexSubspace.range) }
            .flatMap { (keyValueRecords: FDB.KeyValuesResult, transaction: AnyFDBTransaction) -> EventLoopFuture<Void> in
                var result: EventLoopFuture<Void> = eventLoop.makeSucceededFuture()

                for record in keyValueRecords.records {
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
                        return eventLoop.makeFailedFuture(
                            Entita2.E.IndexError(
                                "Could not cast '\(keyNameErased)' as String in entity '\(Self.entityName)'"
                            )
                        )
                    }
                    guard let key = IndexKey(rawValue: keyName) else {
                        Entita2.logger.debug("Unknown index '\(keyName)' in entity '\(Self.entityName)', skipping")
                        continue
                    }
                    guard let index = Self.indices[key] else {
                        Entita2.logger.debug("No index '\(key)' in entity '\(Self.entityName)', skipping")
                        continue
                    }
                    guard let propertyValue = self.getIndexValueFrom(index: index) else {
                        return eventLoop.makeFailedFuture(
                            Entita2.E.IndexError(
                                "Could not get property value for index '\(key)' in entity '\(Self.entityName)'"
                            )
                        )
                    }

                    let probablyNewIndexKey = self.getIndexKeyForIndex(index, key: key, value: propertyValue)
                    let previousIndexKey = self.getIndexKeyForIndex(index, key: key, value: indexValue)

                    if previousIndexKey.asFDBKey() != probablyNewIndexKey.asFDBKey() {
                        result = result
                            .flatMap { _ in transaction.clear(key: previousIndexKey) }
                            .flatMap { _ in transaction.clear(key: indexFDBKey) }
                            .map { _ in () }
                    }
                }

                return result
            }
            .flatMap { self.afterInsert0(within: transaction as? AnyTransaction, on: eventLoop) }
    }

    func afterSave0(
        within transaction: AnyTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        return self.updateIndices(within: transaction as? AnyFDBTransaction, on: eventLoop)
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
        snapshot: Bool = false,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<[Self]> {
        guard Self.isValidIndex(key: key) else {
            return eventLoop.makeSucceededFuture([])
        }

        return Self.storage
            .unwrapAnyTransactionOrBegin(tr, on: eventLoop)
            .flatMap { (transaction: AnyFDBTransaction) -> EventLoopFuture<[Self]> in
                return transaction
                    .get(
                        range: Self.getGenericIndexSubspaceForIndex(key: key, value: value).range,
                        limit: limit,
                        snapshot: snapshot
                    )
                    .flatMap { (results: FDB.KeyValuesResult) -> EventLoopFuture<[Self]> in
                        EventLoopFuture<[Self]>.reduce(
                            into: [],
                            results.records.map {
                                Self.loadByRaw(
                                    IDBytes: $0.value,
                                    within: transaction as? AnyTransaction,
                                    on: eventLoop
                                )
                            },
                            on: eventLoop
                        ) { carry, maybeResult in
                            if let result = maybeResult {
                                carry.append(result)
                            }
                        }
                    }
            }
    }

    static func loadByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within transaction: AnyFDBTransaction? = nil,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Self?> {
        guard Self.isValidIndex(key: key) else {
            return eventLoop.makeSucceededFuture(nil)
        }

        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.get(key: Self.getIndexKeyForUniqueIndex(key: key, value: value)) }
            .flatMap { maybeIDBytes, transaction in
                guard let IDBytes = maybeIDBytes else {
                    return eventLoop.makeSucceededFuture(nil)
                }
                return Self.loadByRaw(
                    IDBytes: IDBytes,
                    within: transaction as? AnyTransaction,
                    on: eventLoop
                )
            }
    }

    static func existsByIndex(
        key: IndexKey,
        value: FDBTuplePackable,
        within transaction: AnyFDBTransaction? = nil,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Bool> {
        guard Self.isValidIndex(key: key) else {
            return eventLoop.makeSucceededFuture(false)
        }

        return Self.storage
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { transaction in
                transaction
                    .get(key: Self.getIndexKeyForUniqueIndex(key: key, value: value))
                    .map { maybeIDBytes, _ in maybeIDBytes != nil }
            }
    }
}
