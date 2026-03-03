import Foundation

final class HelperXPCClient {
    static let machServiceName = "org.evilscheme.MenubarTracert.TracertHelper"

    private var connection: NSXPCConnection?

    func connect() -> TracertHelperProtocol? {
        if let conn = connection {
            return conn.remoteObjectProxyWithErrorHandler { error in
                print("XPC proxy error: \(error)")
            } as? TracertHelperProtocol
        }

        let conn = NSXPCConnection(machServiceName: Self.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: TracertHelperProtocol.self)

        let classes = NSSet(array: [ProbeResultXPC.self, NSString.self, NSNumber.self]) as! Set<AnyHashable>
        conn.remoteObjectInterface?.setClasses(
            classes,
            for: #selector(TracertHelperProtocol.probeRound(host:maxHops:withReply:)),
            argumentIndex: 0,
            ofReply: true
        )

        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }

        conn.resume()
        self.connection = conn

        return conn.remoteObjectProxyWithErrorHandler { error in
            print("XPC proxy error: \(error)")
        } as? TracertHelperProtocol
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
