import NIO

internal extension EventLoop {
    @usableFromInline
    func makeSucceededFuture() -> EventLoopFuture<Void> {
        self.makeSucceededFuture(Void())
    }
}
