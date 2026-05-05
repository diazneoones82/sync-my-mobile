import Foundation
import Network

final class DiscoveryService {
    private var listener: NWListener?
    private var scanTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "sync-my-mobile.mac.discovery")

    func start(onDevice: @escaping @Sendable (Device) -> Void) {
        startUDP(onDevice: onDevice)
        scanTask?.cancel()
        scanTask = Task {
            while !Task.isCancelled {
                await scanLocalNetworks(onDevice: onDevice)
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        scanTask?.cancel()
        scanTask = nil
    }

    func scanOnce(onDevice: @escaping @Sendable (Device) -> Void) {
        Task {
            await scanLocalNetworks(onDevice: onDevice)
        }
    }

    private func startUDP(onDevice: @escaping @Sendable (Device) -> Void) {
        do {
            listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: discoveryPort)!)
        } catch {
            return
        }

        listener?.newConnectionHandler = { connection in
            connection.start(queue: self.queue)
            self.receive(on: connection, onDevice: onDevice)
        }
        listener?.start(queue: queue)
    }

    private func receive(on connection: NWConnection, onDevice: @escaping @Sendable (Device) -> Void) {
        connection.receiveMessage { data, _, _, _ in
            if let data,
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               payload["app"] as? String == appID,
               let port = payload["port"] as? Int {
                let name = payload["deviceName"] as? String ?? "Mobile Device"
                if case let .hostPort(host, _) = connection.endpoint {
                    let hostText = Self.hostString(host)
                    onDevice(Device(id: "\(hostText):\(port)", name: name, host: hostText, port: port, lastSeen: Date()))
                }
            }
            self.receive(on: connection, onDevice: onDevice)
        }
    }

    private func scanLocalNetworks(onDevice: @escaping @Sendable (Device) -> Void) async {
        let hosts = Self.candidateHosts()
        guard !hosts.isEmpty else {
            return
        }

        await withTaskGroup(of: Device?.self) { group in
            for host in hosts {
                group.addTask {
                    await Self.probe(host: host)
                }
            }

            for await device in group {
                if let device {
                    onDevice(device)
                }
            }
        }
    }

    private static func probe(host: String) async -> Device? {
        guard let baseURL = URL(string: "http://\(host):\(defaultHTTPPort)") else {
            return nil
        }
        do {
            let manifest = try await DeviceAPI(baseURL: baseURL, timeout: 0.75).manifest(timeout: 0.75)
            guard manifest.app == appID else {
                return nil
            }
            return Device(
                id: "\(host):\(defaultHTTPPort)",
                name: manifest.deviceName.isEmpty ? "Mobile Device" : manifest.deviceName,
                host: host,
                port: Int(defaultHTTPPort),
                lastSeen: Date()
            )
        } catch {
            return nil
        }
    }

    private static func candidateHosts() -> [String] {
        var networks = Set<String>()
        for address in localIPv4Addresses() {
            let parts = address.split(separator: ".")
            guard parts.count == 4 else {
                continue
            }
            networks.insert(parts.prefix(3).joined(separator: "."))
        }

        var hosts: [String] = []
        for network in networks {
            for value in 1...254 {
                hosts.append("\(network).\(value)")
            }
        }
        return hosts
    }

    private static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }
        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let flags = Int32(item.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }
            let address = item.pointee.ifa_addr
            guard address?.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address!.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                addresses.append(String(cString: host))
            }
        }
        return addresses
    }

    private static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            return "\(address)"
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }
}
