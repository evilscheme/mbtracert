import Foundation

// MARK: - XPC Service Implementation

final class TracertHelperService: NSObject, TracertHelperProtocol {
    private let engine = ICMPEngine()

    func probeRound(host: String, maxHops: Int, withReply reply: @escaping (ProbeResultXPC) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            let results = engine.probeRound(host: host, maxHops: maxHops)
            for result in results {
                reply(ProbeResultXPC(
                    hop: result.hop,
                    address: result.address,
                    latencyMs: result.latencyMs,
                    timestamp: CFAbsoluteTimeGetCurrent()
                ))
            }
            reply(ProbeResultXPC(hop: -1, address: "", latencyMs: -1, timestamp: CFAbsoluteTimeGetCurrent()))
        }
    }

    func ping(withReply reply: @escaping (String) -> Void) {
        reply("pong")
    }
}

// MARK: - XPC Listener Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: TracertHelperProtocol.self)

        let classes = NSSet(array: [ProbeResultXPC.self, NSString.self, NSNumber.self]) as! Set<AnyHashable>
        conn.exportedInterface?.setClasses(
            classes,
            for: #selector(TracertHelperProtocol.probeRound(host:maxHops:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )

        conn.exportedObject = TracertHelperService()
        conn.resume()
        return true
    }
}

// MARK: - Entry Point

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "org.evilscheme.MenubarTracert.TracertHelper")
listener.delegate = delegate
listener.resume()

RunLoop.current.run()
