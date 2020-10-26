import FDB
import NIO

public typealias E2FDBStorage = Entita2FDBStorage

public protocol Entita2FDBStorage: Entita2Storage, AnyFDB {
    /// Unwraps a given optional `AnyFDBTransaction` transaction into a non-optional transaction or begins a new one
    func unwrapAnyTransactionOrBegin(
        _ anyTransaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<AnyFDBTransaction>

    /// Commits a given transaction if `commit` is `true`
    func commitIfNecessary(
        transaction: AnyFDBTransaction,
        commit: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void>

    /// Tries to load a value from FDB by given key within a given optional transaction
    func load(
        by key: Bytes,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Bytes?>

    /// Tries to load a value from FDB by given key within a given optional transaction (uses snapshot)
    func load(
        by key: Bytes,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Bytes?>

    /// Loads all values from FDB by given range key within a given optional transaction
    func loadAll(
        by range: FDB.RangeKey,
        limit: Int32,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<FDB.KeyValuesResult>

    /// Loads all values from FDB by given range key within a given optional transaction (uses snapshot)
    func loadAll(
        by range: FDB.RangeKey,
        limit: Int32,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<FDB.KeyValuesResult>

    /// Saves given bytes in FDB at given key within an optional transaction
    func save(
        bytes: Bytes,
        by key: Bytes,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void>

    /// Deletes a value from FDB at given key within an optional transaction
    func delete(by key: Bytes, within transaction: AnyFDBTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void>
}

extension FDB: Entita2FDBStorage {
    public func begin(on eventLoop: EventLoop) -> EventLoopFuture<AnyTransaction> {
        self.begin(on: eventLoop).map { (fdbTransaction: AnyFDBTransaction) -> AnyTransaction in
            fdbTransaction as! AnyTransaction
        }
    }

    // MARK: - Entita2FDBStorage compatibility layer
    @inlinable public func unwrapAnyTransactionOrBegin(
        _ anyTransaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<AnyFDBTransaction> {
        if let transaction = anyTransaction {
            return eventLoop.makeSucceededFuture(transaction)
        } else {
            Entita2.logger.debug("Beginning a new transaction")
            return self.begin(on: eventLoop)
        }
    }

    @inlinable public func commitIfNecessary(
        transaction: AnyFDBTransaction,
        commit: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        commit
            ? transaction.commit()
            : eventLoop.makeSucceededFuture()
    }

    public func load(
        by key: Bytes,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Bytes?> {
        self.load(by: key, within: transaction, snapshot: false, on: eventLoop)
    }

    public func load(
        by key: Bytes,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Bytes?> {
        self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { transaction in transaction.get(key: key, snapshot: snapshot) }
            .map { $0.0 }
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
        self.loadAll(by: range, limit: limit, within: transaction, snapshot: false, on: eventLoop)
    }

    public func loadAll(
        by range: FDB.RangeKey,
        limit: Int32 = 0,
        within transaction: AnyFDBTransaction?,
        snapshot: Bool,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<FDB.KeyValuesResult> {
        self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.get(range: range, limit: limit, snapshot: snapshot) }
            .map { $0.0 }
    }

    public func save(
        bytes: Bytes,
        by key: Bytes,
        within transaction: AnyFDBTransaction?,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.set(key: key, value: bytes) }
            .flatMap { self.commitIfNecessary(transaction: $0, commit: transaction == nil, on: eventLoop) }
    }

    public func delete(by key: Bytes, within transaction: AnyFDBTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        self
            .unwrapAnyTransactionOrBegin(transaction, on: eventLoop)
            .flatMap { $0.clear(key: key) }
            .flatMap { self.commitIfNecessary(transaction: $0, commit: transaction == nil, on: eventLoop) }
    }

    // MARK: - Entita2Storage compatibility layer

    public func load(by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Bytes?> {
        self.load(by: key, within: transaction as? AnyFDBTransaction, snapshot: false, on: eventLoop)
    }

    public func save(bytes: Bytes, by key: Bytes, within tr: AnyTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        self.save(bytes: bytes, by: key, within: tr as? AnyFDBTransaction, on: eventLoop)
    }

    public func delete(by key: Bytes, within transaction: AnyTransaction?, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        self.delete(by: key, within: transaction as? AnyFDBTransaction, on: eventLoop)
    }
}
