import Foundation
import Network
import UIKit

final class UdpBeacon {
    private let httpPort: UInt16
    private let queue = DispatchQueue(label: "sync-my-mobile.udp-beacon")
    private var timer: DispatchSourceTimer?

    init(httpPort: UInt16) {
        self.httpPort = httpPort
    }

    func start() {
        if timer != nil {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.broadcast()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func broadcast() {
        let payload = #"{"app":"\#(appID)","deviceName":"\#(escape(UIDevice.current.name))","port":\#(httpPort)}"#
        let connection = NWConnection(
            host: NWEndpoint.Host("255.255.255.255"),
            port: NWEndpoint.Port(rawValue: discoveryPort)!,
            using: .udp,
        )
        connection.start(queue: queue)
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
