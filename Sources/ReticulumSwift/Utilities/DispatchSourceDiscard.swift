import Dispatch

extension DispatchSourceProtocol {

    /// Discard a dispatch source that was created but never started.
    ///
    /// `cancel()` alone is not enough, and getting this wrong kills the process rather than
    /// leaking. A source returned by `DispatchSource.make…Source` begins **suspended**, and
    /// libdispatch traps when a suspended object's last reference is released — cancelled or
    /// not:
    ///
    ///     BUG IN CLIENT OF LIBDISPATCH: Release of a suspended object
    ///     → EXC_BREAKPOINT / SIGTRAP in _dispatch_queue_xref_dispose
    ///
    /// Verified directly, because the four lifecycles are easy to conflate and only one of them
    /// is fatal:
    ///
    /// | lifecycle before release          | outcome  |
    /// |-----------------------------------|----------|
    /// | create → cancel                   | **trap** |
    /// | create → resume                   | safe     |
    /// | create → resume → cancel          | safe     |
    /// | create → cancel → resume          | safe     |
    ///
    /// So an abandoned source must be resumed to clear its suspension, even though it will never
    /// fire. `resume()` after `cancel()` is a no-op on delivery and legal — the last row above.
    ///
    /// Every site that builds a source and then decides not to install it — a concurrent
    /// `stop()`, a link that went terminal while a tick was in flight — must use this rather
    /// than `cancel()`. See `bugs/032`, and the structural guard in
    /// `DispatchSourceDiscardTests` that pins it.
    func cancelUnstarted() {
        cancel()
        // Clears the initial suspension so the release below is legal. Not redundant: without
        // it this whole function is the crash.
        resume()
    }
}
