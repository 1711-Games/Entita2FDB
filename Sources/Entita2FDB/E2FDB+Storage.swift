import Entita2
import FDB
import LGNLog

public typealias E2FDBStorage = Entita2FDBStorage

extension Entita2Storage where Self == FDB.Connector {
    
}

public protocol Entita2FDBStorage: Entita2Storage, FDBConnector {
    /// Unwraps a given optional `any FDBTransaction` transaction into a non-optional transaction or begins a new one
    func unwrapAnyTransactionOrBegin(_ anyTransaction: (any FDBTransaction)?) async throws -> any FDBTransaction

    /// Commits a given transaction if `commit` is `true`
    func commitIfNecessary(transaction: any FDBTransaction, commit: Bool) async throws

    /// Tries to load a value from FDB by given key within a given optional transaction
    func load(by key: Bytes, within transaction: (any FDBTransaction)?) async throws -> Bytes?

    /// Tries to load a value from FDB by given key within a given optional transaction (uses snapshot)
    func load(by key: Bytes, within transaction: (any FDBTransaction)?, snapshot: Bool) async throws -> Bytes?

    /// Loads all values from FDB by given range key within a given optional transaction
    func loadAll(by range: FDB.RangeKey, limit: Int32, within transaction: (any FDBTransaction)?) async throws -> FDB.KeyValuesResult

    /// Loads all values from FDB by given range key within a given optional transaction (uses snapshot)
    func loadAll(
        by range: FDB.RangeKey,
        limit: Int32,
        within transaction: (any FDBTransaction)?,
        snapshot: Bool
    ) async throws -> FDB.KeyValuesResult

    /// Saves given bytes in FDB at given key within an optional transaction
    func save(bytes: Bytes, by key: Bytes, within transaction: (any FDBTransaction)?) async throws

    /// Deletes a value from FDB at given key within an optional transaction
    func delete(by key: Bytes, within transaction: (any FDBTransaction)?) async throws
}

extension FDB.Connector: Entita2FDBStorage {
    public func begin() throws -> any Entita2Transaction {
        let transaction: any FDBTransaction = try self.begin()
        return transaction as! Entita2Transaction
    }

    // MARK: - Entita2FDBStorage compatibility layer
    @inlinable
    public func unwrapAnyTransactionOrBegin(_ anyTransaction: (any FDBTransaction)?) throws -> any FDBTransaction {
        if let transaction = anyTransaction {
            return transaction
        } else {
            Logger.current.debug("Beginning a new transaction")
            return try self.begin()
        }
    }

    @inlinable
    public func commitIfNecessary(transaction: any FDBTransaction, commit: Bool) async throws {
        if commit {
            try await transaction.commit()
        }
    }

    public func load(by key: Bytes, within transaction: (any FDBTransaction)?) async throws -> Bytes? {
        try await self.load(by: key, within: transaction, snapshot: false)
    }

    public func load(by key: Bytes, within maybeTransaction: (any FDBTransaction)?, snapshot: Bool) async throws -> Bytes? {
        try await self
            .unwrapAnyTransactionOrBegin(maybeTransaction)
            .get(key: key, snapshot: snapshot)
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within transaction: (any FDBTransaction)?
    ) async throws -> FDB.KeyValuesResult {
        try await self.loadAll(by: range, limit: limit, within: transaction, snapshot: false)
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within maybeTransaction: (any FDBTransaction)?,
        snapshot: Bool
    ) async throws -> FDB.KeyValuesResult {
        try await self
            .unwrapAnyTransactionOrBegin(maybeTransaction)
            .get(range: range, limit: limit, snapshot: snapshot)
    }

    public func save(bytes: Bytes, by key: Bytes, within maybeTransaction: (any FDBTransaction)?) async throws {
        let transaction = try self.unwrapAnyTransactionOrBegin(maybeTransaction)
        transaction.set(key: key, value: bytes)
        try await self.commitIfNecessary(transaction: transaction, commit: maybeTransaction == nil)
    }

    public func delete(by key: Bytes, within maybeTransaction: (any FDBTransaction)?) async throws {
        let transaction = try self.unwrapAnyTransactionOrBegin(maybeTransaction)
        transaction.clear(key: key)
        try await self.commitIfNecessary(transaction: transaction, commit: maybeTransaction == nil)
    }

    // MARK: - Entita2Storage compatibility layer

    public func load(by key: Bytes, within transaction: (any Entita2Transaction)?) async throws -> Bytes? {
        try await self.load(by: key, within: transaction as? any FDBTransaction, snapshot: false)
    }

    public func save(bytes: Bytes, by key: Bytes, within tr: (any Entita2Transaction)?) async throws {
        try await self.save(bytes: bytes, by: key, within: tr as? any FDBTransaction)
    }

    public func delete(by key: Bytes, within transaction: (any Entita2Transaction)?) async throws {
        try await self.delete(by: key, within: transaction as? any FDBTransaction)
    }
}
