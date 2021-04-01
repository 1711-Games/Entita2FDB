import FDB

public typealias E2FDBStorage = Entita2FDBStorage

public protocol Entita2FDBStorage: Entita2Storage, AnyFDB {
    /// Unwraps a given optional `AnyFDBTransaction` transaction into a non-optional transaction or begins a new one
    func unwrapAnyTransactionOrBegin(_ anyTransaction: AnyFDBTransaction?) async throws -> AnyFDBTransaction

    /// Commits a given transaction if `commit` is `true`
    func commitIfNecessary(transaction: AnyFDBTransaction, commit: Bool) async throws

    /// Tries to load a value from FDB by given key within a given optional transaction
    func load(by key: Bytes, within transaction: AnyFDBTransaction?) async throws -> Bytes?

    /// Tries to load a value from FDB by given key within a given optional transaction (uses snapshot)
    func load(by key: Bytes, within transaction: AnyFDBTransaction?, snapshot: Bool) async throws -> Bytes?

    /// Loads all values from FDB by given range key within a given optional transaction
    func loadAll(by range: FDB.RangeKey, limit: Int32, within transaction: AnyFDBTransaction?) async throws -> FDB.KeyValuesResult

    /// Loads all values from FDB by given range key within a given optional transaction (uses snapshot)
    func loadAll(
        by range: FDB.RangeKey,
        limit: Int32,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool
    ) async throws -> FDB.KeyValuesResult

    /// Saves given bytes in FDB at given key within an optional transaction
    func save(bytes: Bytes, by key: Bytes, within transaction: AnyFDBTransaction?) async throws

    /// Deletes a value from FDB at given key within an optional transaction
    func delete(by key: Bytes, within transaction: AnyFDBTransaction?) async throws
}

extension FDB: Entita2FDBStorage {
    public func begin() throws -> AnyTransaction {
        let transaction: AnyFDBTransaction = try self.begin()
        return transaction as! AnyTransaction
    }

    // MARK: - Entita2FDBStorage compatibility layer
    @inlinable
    public func unwrapAnyTransactionOrBegin(_ anyTransaction: AnyFDBTransaction?) throws -> AnyFDBTransaction {
        if let transaction = anyTransaction {
            return transaction
        } else {
            Entita2.logger.debug("Beginning a new transaction")
            return try self.begin()
        }
    }

    @inlinable
    public func commitIfNecessary(transaction: AnyFDBTransaction, commit: Bool) async throws {
        if commit {
            try await transaction.commit()
        }
    }

    public func load(by key: Bytes, within transaction: AnyFDBTransaction?) async throws -> Bytes? {
        try await self.load(by: key, within: transaction, snapshot: false)
    }

    public func load(by key: Bytes, within maybeTransaction: AnyFDBTransaction?, snapshot: Bool) async throws -> Bytes? {
        try await self
            .unwrapAnyTransactionOrBegin(maybeTransaction)
            .get(key: key, snapshot: snapshot)
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within transaction: AnyFDBTransaction?
    ) async throws -> FDB.KeyValuesResult {
        try await self.loadAll(by: range, limit: limit, within: transaction, snapshot: false)
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within maybeTransaction: AnyFDBTransaction?,
        snapshot: Bool
    ) async throws -> FDB.KeyValuesResult {
        try await self
            .unwrapAnyTransactionOrBegin(maybeTransaction)
            .get(range: range, limit: limit, snapshot: snapshot)
    }

    public func save(bytes: Bytes, by key: Bytes, within maybeTransaction: AnyFDBTransaction?) async throws {
        let transaction = try self.unwrapAnyTransactionOrBegin(maybeTransaction)
        transaction.set(key: key, value: bytes)
        try await self.commitIfNecessary(transaction: transaction, commit: maybeTransaction == nil)
    }

    public func delete(by key: Bytes, within maybeTransaction: AnyFDBTransaction?) async throws {
        let transaction = try self.unwrapAnyTransactionOrBegin(maybeTransaction)
        transaction.clear(key: key)
        try await self.commitIfNecessary(transaction: transaction, commit: maybeTransaction == nil)
    }

    // MARK: - Entita2Storage compatibility layer

    public func load(by key: Bytes, within transaction: AnyTransaction?) async throws -> Bytes? {
        try await self.load(by: key, within: transaction as? AnyFDBTransaction, snapshot: false)
    }

    public func save(bytes: Bytes, by key: Bytes, within tr: AnyTransaction?) async throws {
        try await self.save(bytes: bytes, by: key, within: tr as? AnyFDBTransaction)
    }

    public func delete(by key: Bytes, within transaction: AnyTransaction?) async throws {
        try await self.delete(by: key, within: transaction as? AnyFDBTransaction)
    }
}
