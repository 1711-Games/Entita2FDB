import Foundation
import FDB

extension Entita2.ID: FDBTuplePackable where Value == UUID {
    @inlinable
    public func pack() -> Bytes {
        self._bytes.pack()
    }
}
