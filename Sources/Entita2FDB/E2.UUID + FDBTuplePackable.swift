import Foundation
import FDB

extension Entita2.ID: FDBTuplePackable where Value == UUID {
    @inlinable
    public func getPackedFDBTupleValue() -> Bytes {
        self._bytes.getPackedFDBTupleValue()
    }
}
