import Foundation
import FDB

extension E2.ID: FDBTuplePackable where Value == UUID {
    @inlinable public func pack() -> Bytes {
        return self._bytes.pack()
    }
}
