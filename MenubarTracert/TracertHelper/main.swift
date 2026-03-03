import Foundation

// MARK: - XPC Service Implementation

final class TracertHelperService: NSObject, TracertHelperProtocol {
    private let engine = ICMPEngine()

    func probeRound(host: String, maxHops: Int, withReply reply: @escaping ([ProbeResultXPC]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            let results = engine.probeRound(host: host, maxHops: maxHops)
            let xpcResults = results.map { result in
                ProbeResultXPC(
                    hop: result.hop,
                    address: result.address,
                    latencyMs: result.latencyMs,
                    timestamp: CFAbsoluteTimeGetCurrent()
                )
            }
            reply(xpcResults)
        }
    }

    func ping(withReply reply: @escaping (String) -> Void) {
        reply("pong")
    }
}

// MARK: - XPC Listener Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        NSLog("[TracertHelper] Accepting new XPC connection")
        conn.exportedInterface = NSXPCInterface(with: TracertHelperProtocol.self)

        let classes = NSSet(array: [ProbeResultXPC.self, NSArray.self, NSString.self, NSNumber.self]) as! Set<AnyHashable>
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

NSLog("[TracertHelper] Starting up, PID=%d", ProcessInfo.processInfo.processIdentifier)

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "org.evilscheme.MenubarTracert.TracertHelper")
listener.delegate = delegate
listener.resume()

NSLog("[TracertHelper] Listener active, entering run loop")
RunLoop.current.run()
