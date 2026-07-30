import XCTest
@testable import ReticulumSwift

/// Configure an interface's IFAC the way a config file does, for tests.
///
/// `bugs/015` and design D10. `IFACTests` and `IFACSendPathTests` called
/// `Transport.configureIfac` directly — twenty-three sites between them — and proved the masking
/// implementation in detail while the production path that was supposed to call it did not exist.
/// The package therefore looked comprehensively IFAC-tested, which is why nobody looked.
///
/// So every IFAC assertion in this package now enters through `Reticulum.applyIfacConfiguration`,
/// the same entry point `synthesizeInterfaces` uses. If that call site is ever removed again, the
/// failure is wide rather than absent.
///
/// Keys are spelled as they are in a config block, not as Swift parameters, so the tests also
/// exercise the spellings Python accepts.
func configureIfacFromConfigBlock(on interface: any Interface,
                                  netname: String? = nil,
                                  netkey: String? = nil,
                                  sizeBits: Int? = nil) {
    var parameters: [String: String] = [:]
    if let netname { parameters["network_name"] = netname }
    if let netkey { parameters["passphrase"] = netkey }
    if let sizeBits { parameters["ifac_size"] = String(sizeBits) }
    Reticulum.applyIfacConfiguration(
        to: interface,
        from: ReticulumConfig.InterfaceConfig(name: interface.name,
                                              type: "UDPInterface",
                                              enabled: true,
                                              parameters: parameters))
}
