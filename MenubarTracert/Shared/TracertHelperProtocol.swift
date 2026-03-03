import Foundation

@objc public class ProbeResultXPC: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let hop: Int
    @objc public let address: String
    @objc public let latencyMs: Double
    @objc public let timestamp: Double

    public init(hop: Int, address: String, latencyMs: Double, timestamp: Double) {
        self.hop = hop
        self.address = address
        self.latencyMs = latencyMs
        self.timestamp = timestamp
    }

    public func encode(with coder: NSCoder) {
        coder.encode(hop, forKey: "hop")
        coder.encode(address, forKey: "address")
        coder.encode(latencyMs, forKey: "latencyMs")
        coder.encode(timestamp, forKey: "timestamp")
    }

    public required init?(coder: NSCoder) {
        self.hop = coder.decodeInteger(forKey: "hop")
        self.address = (coder.decodeObject(of: NSString.self, forKey: "address") as? String) ?? ""
        self.latencyMs = coder.decodeDouble(forKey: "latencyMs")
        self.timestamp = coder.decodeDouble(forKey: "timestamp")
        super.init()
    }
}

@objc public protocol TracertHelperProtocol {
    func probeRound(
        host: String,
        maxHops: Int,
        withReply reply: @escaping (ProbeResultXPC) -> Void
    )

    func ping(withReply reply: @escaping (String) -> Void)
}
