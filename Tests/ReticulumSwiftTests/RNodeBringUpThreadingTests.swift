import XCTest
@testable import ReticulumSwift

/// The bring-up gate (`bugs/057`) must not require its caller to be on a *different* thread from
/// the one the transport delivers bytes on — because for the port's only real BLE transport, they
/// are the same thread.
///
/// `RetiOS`'s `RNodeScannerController` creates its `CBCentralManager` with one serial queue and
/// calls `RNodeInterface.start()` from `onGATTReady`, which CoreBluetooth invokes on that same
/// queue. Every subsequent delegate callback — including `didUpdateValueFor`, the only thing that
/// can set `detected` — is queued behind whatever is running there. A `start()` that blocks that
/// thread waiting for the detect response is waiting for work it is itself preventing: the wait
/// can only ever time out, the transport then closes, and the interface stays offline forever.
///
/// This is `bugs/058`'s own lesson turned on the fix for `bugs/057`: a component must not depend
/// on a scheduling property its callers cannot be relied on to have. So `start()` never blocks the
/// caller; the bring-up runs on a queue the interface owns, and callers that want the old
/// synchronous behaviour ask for it explicitly.
final class RNodeBringUpThreadingTests: XCTestCase {

    /// A transport whose byte delivery is serialized on the **same** queue its caller uses —
    /// the CoreBluetooth shape. `write` hands the response to `deliveryQueue` rather than
    /// calling `byteHandler` inline, so a blocked delivery queue really does starve it.
    private final class QueueDeliveredTransport: RNodeTransport {
        var byteHandler: ((Data) -> Void)?
        var onTransportError: ((Error) -> Void)?
        let deliveryQueue: DispatchQueue
        weak var echoSource: RNodeInterface?

        init(deliveryQueue: DispatchQueue) { self.deliveryQueue = deliveryQueue }

        func open() throws {}
        func close() {}

        func write(_ data: Data) throws {
            let bytes = [UInt8](data)
            guard bytes.count > 1, bytes[1] == KISS.cmdDetect else { return }
            deliveryQueue.async { [weak self] in
                guard let self, let iface = self.echoSource else { return }
                var reply = Data([KISS.fend, KISS.cmdDetect, KISS.detectResp, KISS.fend])
                func frame(_ cmd: UInt8, _ payload: [UInt8]) {
                    reply.append(KISS.fend); reply.append(cmd)
                    reply.append(contentsOf: payload); reply.append(KISS.fend)
                }
                func be32(_ v: UInt32) -> [UInt8] {
                    [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF),
                     UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
                }
                frame(KISS.cmdFrequency, be32(iface.frequency))
                frame(KISS.cmdBandwidth, be32(iface.bandwidth))
                frame(KISS.cmdTxpower, [UInt8(clamping: iface.txPower)])
                frame(KISS.cmdSf, [UInt8(clamping: iface.sf)])
                frame(KISS.cmdCr, [UInt8(clamping: iface.cr)])
                frame(KISS.cmdRadioState, [KISS.radioStateOn])
                self.byteHandler?(reply)
            }
        }
    }

    private func configured(_ iface: RNodeInterface) -> RNodeInterface {
        iface.frequency = 869_525_000
        iface.bandwidth = 125_000
        iface.txPower = 7
        iface.sf = 8
        iface.cr = 5
        return iface
    }

    func testStartDoesNotBlockTheThreadThatDeliversBytes() throws {
        let deliveryQueue = DispatchQueue(label: "test.ble.serial")
        let transport = QueueDeliveredTransport(deliveryQueue: deliveryQueue)
        let iface = configured(RNodeInterface(name: "BLE LoRa", transport: transport))
        transport.echoSource = iface

        // Exactly RetiOS's shape: start() is called *from* the delivery queue.
        let returned = expectation(description: "start() returned")
        deliveryQueue.async {
            try? iface.start()
            returned.fulfill()
        }
        wait(for: [returned], timeout: 2.0)

        // If start() blocked here, the detect response — which can only be delivered on this same
        // queue — could not arrive until after the wait had already given up.
        let deadline = Date().addingTimeInterval(3.0)
        while !iface.isOnline && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(iface.isOnline,
                      """
                      the interface never came online over a transport that delivers bytes on the \
                      caller's own serial queue — the bring-up wait starved the very response it \
                      was waiting for. This is RetiOS's real BLE path (RNodeScannerController \
                      calls start() from onGATTReady, on the CBCentralManager queue).
                      """)
        iface.stop()
    }

    /// The caller must be able to ask for the old synchronous behaviour where it is safe —
    /// `rnsd` bringing up a config-file interface, where nothing else owns the thread.
    func testACallerCanWaitForTheBringUpExplicitly() throws {
        let transport = QueueDeliveredTransport(
            deliveryQueue: DispatchQueue(label: "test.transport.delivery"))
        let iface = configured(RNodeInterface(name: "Serial LoRa", transport: transport))
        transport.echoSource = iface

        try iface.start()
        XCTAssertTrue(iface.waitUntilOnline(timeout: 3.0),
                      "a caller that is not on the delivery thread must be able to block until "
                      + "the interface is up, as the reference's constructor does")
        XCTAssertTrue(iface.isOnline)
        iface.stop()
    }

    func testWaitingReportsFailureRatherThanHangingWhenNoDeviceAnswers() throws {
        final class SilentTransport: RNodeTransport {
            var byteHandler: ((Data) -> Void)?
            var onTransportError: ((Error) -> Void)?
            private(set) var closed = false
            func open() throws {}
            func close() { closed = true }
            func write(_ data: Data) throws {}
        }
        let transport = SilentTransport()
        let iface = configured(RNodeInterface(name: "Absent", transport: transport))
        iface.detectTimeout = 0.1

        try iface.start()
        XCTAssertFalse(iface.waitUntilOnline(timeout: 2.0),
                       "waiting on a device that never answers must return false, not hang")
        XCTAssertFalse(iface.isOnline)
        XCTAssertTrue(transport.closed, "a failed bring-up closes the transport")
    }
}
