# Entita2FDB

Entita2FDB is an extension of an ORM Entita2 for working with FoundationDB, a highly distributed transactional NoSQL DB
by Apple.
It uses [FDBSwift](https://github.com/kirilltitov/FDBSwift) package as connector to database. 

## Entity definition

```swift
import struct Foundation
import Entita2FDB

// ... somewhere, like in main.swift
let fdb = FDB()

final class User: Entita2FDBEntity {
    public typealias Identifier = E2.UUID

    public static var format: E2.Format = .JSON
    public static var IDKey: KeyPath<User, E2.UUID> = \.ID

    public static var subspace: FDB.Subspace = FDB.Subspace("subspace_prefix")
    public static var storage: some Entita2FDBStorage = fdb

    public let ID: E2.UUID

    public var username: String
    public var password: String
    public var email: String
    public var country: String
    public var dateSignup: Date
    public var dateLogin: Date?

    public init(
        username: String,
        password: String,
        email: String,
        country: String,
        dateSignup: Date = Date(),
        dateLogin: Date? = nil
    ) {
        self.ID = .init()
        self.username = username
        self.password = password
        self.email = email
        self.country = country
        self.dateSignup = dateSignup
        self.dateLogin = dateLogin
    }
}
```

NB: Every `Entita2`-prefixed definition has a `E2`-prefixed typealias:
`Entita2` >> `E2`, `Entita2Entity` >> `E2Entity` etc.

This snippet defines an entity `User` with an UUID identifier (identifiers can be anything, including `Int`, of course)
and a few more properties. Under the hood Entita2 utilizes `Codable` protocol, so every property must conform to it.
The entity is packed using JSON format (other option is MessagePack). ID property can be named anything, and therefore
a KeyPath should be provided to this property.

As for FDB-related stuff: `E2FDBEntity` requires your entity to have two static variables:
* `subspace`, an FDB subspace (namespace, if you wish), under which this entity will be stored. You don't have
to specify entity name in this subspace, as it will be added automatically. In other words, this subspace is abstract
for all entities, and will be specialized for this entity by `E2FDB` automatically.
* `storage` of type `some Entita2FDBStorage`, a reference to DB connector. Under the hood `E2FDBStorage` is a protocol
combining `AnyFDB` protocol and some helper methods. Currently only `FDB` class adopts this protocol,
but you may create a dummy implementation for tests (though it's easier to use actual FDB and a disposable subspace).

## CRUD

CRUD API is the same as in basic `Entita2` package,
please refer to [E2 documentation](https://github.com/1711-Games/Entita2#crud).

## Indices

This package also provides basic support for raw indices for your entities. For that purpose please adopt protocol
`Entita2FDBIndexedEntity` (or alias `E2FDBIndexedEntity`). It extends basic `E2FDBEntity` protocol with some more
requirements, like:
* `IndexKey` associated type (of `AnyIndexKey`), basically an enum with all possible index keys.
* a static dictionary `indices: [IndexKey: E2.Index<Self>]` with indices schema.
`E2.Index` (an alias for `Entita2.Index`) is a simple struct with just an initializer which accepts a keypath to the
indexed property and a `unique: Bool` flag, which is self-explanatory.

### Complete example

Let's extend entity above with indices:

```swift
final class User: Entita2FDBIndexedEntity {
    public enum IndexKey: String, AnyIndexKey {
        case username, email, country
    }
    
    public static var indices: [IndexKey: E2.Index<User>] = [
        .username: E2.Index(\.username, unique: true),
        .email   : E2.Index(\.email,    unique: true),
        .country : E2.Index(\.country,  unique: false),
    ]

    // everything else is the same
}
```

Here we indexed three properties: username, email (unique indices) and country (non-unique). Thus we will be able to
load this entity directly by unique properties (username/email), or load all entities by certain country using
following methods:

* Loads all entities by given index. If index is unique, array may only contain one item.

```swift
static func loadAllByIndex(
    key: IndexKey,
    value: FDBTuplePackable,
    limit: Int32 = 0,
    within tr: (any FDBTransaction)? = nil,
    snapshot: Bool = false
) async throws -> [Self]
```

* Tries to load an entity by given unique index.

```swift
static func loadByIndex(
    key: IndexKey,
    value: FDBTuplePackable,
    within transaction: (any FDBTransaction)? = nil
) async throws -> Self?
```

* Returns true if entity exists by given unique index.

```swift
static func existsByIndex(
    key: IndexKey,
    value: FDBTuplePackable,
    within transaction: (any FDBTransaction)? = nil
) async throws -> Bool
```

### Warning

Do not define `afterInsert0`/`beforeDelete0`/`afterSave0` methods from basic `E2Entity` protocol, because indices engine
relies on those methods.

## Transactions

You might've noticed that methods above (as well as generic CRUD methods) accept optional transactions,
though by default all methods are transactionless (i.e. every request is implicitly transactional under the hood).

In order to execute more than one operation within a transaction, you may create one by
`let transaction: any FDBTransaction = fdb.begin()` and then pass to every CRUD/index method.

Or you may wrap all your routine code with a transaction like this:

```swift
try await fdb.withTransaction { transaction in
    let maybeUser = try await User.load(by: E2.UUID("9C0FDD1C-FE56-4598-A037-177362DBD3D2")!, within: transaction)

    guard let user = maybeUser else {
        throw AppError.UserNotFound
    }

    user.dateLogin = Date()

    try await user.save(within: transaction, commit: false)

    // `save` above commits by default, but in this case it was explicitly disabled
    transaction.commit()
}
```

For more details on FoundationDB transactions (as well as specific details on FDBSwift transactions) please refer to a
[respective FDBSwift documentation section](https://github.com/kirilltitov/FDBSwift#transactions).
