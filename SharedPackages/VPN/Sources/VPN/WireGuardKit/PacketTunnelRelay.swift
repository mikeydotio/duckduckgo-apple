//
//  PacketTunnelRelay.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import NetworkExtension
import os.log

/// Bridges `NEPacketTunnelFlow` (packetFlow) and WireGuard via a `socketpair`.
///
/// Instead of WireGuard reading the real utun fd directly, we give it one end of
/// a socketpair. We read from `packetFlow` ourselves and forward packets through
/// the socketpair. This gives us an interception point for every packet — including UDP.
///
/// ```
/// App → kernel → utun → packetFlow.readPackets()
///        → [PacketTunnelRelay: inspect/filter] →
///        → socketpair fd → WireGuard Go (encrypt → VPN server)
///
/// VPN server → WireGuard Go (decrypt) → socketpair fd
///        → [PacketTunnelRelay] →
///        → packetFlow.writePackets() → kernel → App
/// ```
final class PacketTunnelRelay: TunnelFileDescriptorProviding {

    private var wireGuardFd: Int32 = -1  // WireGuard reads/writes this end
    private var relayFd: Int32 = -1      // We read/write this end
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.duckduckgo.network-protection.PacketTunnelRelay")

    init() {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &fds) == 0 else {
            Logger.networkProtection.error("🦆 [Relay] socketpair creation failed: \(errno)")
            return
        }
        wireGuardFd = fds[0]
        relayFd = fds[1]

        // Set large buffer sizes for packet-sized datagrams
        var bufSize: Int32 = 2 * 1024 * 1024
        setsockopt(wireGuardFd, SOL_SOCKET, SO_SNDBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(wireGuardFd, SOL_SOCKET, SO_RCVBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(relayFd, SOL_SOCKET, SO_SNDBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(relayFd, SOL_SOCKET, SO_RCVBUF, &bufSize, socklen_t(MemoryLayout<Int32>.size))

        Logger.networkProtection.log("🦆 [Relay] Created socketpair: wg=\(fds[0]), relay=\(fds[1])")
    }

    // MARK: - TunnelFileDescriptorProviding

    func currentFileDescriptor() -> Int32? {
        guard wireGuardFd >= 0 else { return nil }
        return wireGuardFd
    }

    // MARK: - Relay

    func start(packetFlow: NEPacketTunnelFlow) {
        Logger.networkProtection.log("🦆 [Relay] Starting packet relay")
        startOutgoingRelay(packetFlow: packetFlow)
        startIncomingRelay(packetFlow: packetFlow)
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if relayFd >= 0 { close(relayFd) }
        if wireGuardFd >= 0 { close(wireGuardFd) }
        relayFd = -1
        wireGuardFd = -1
    }

    // MARK: - Outgoing (packetFlow → socketpair → WireGuard)

    private func startOutgoingRelay(packetFlow: NEPacketTunnelFlow) {
        func readLoop() {
            packetFlow.readPackets { [weak self] packets, protocols in
                guard let self, self.relayFd >= 0 else { return }

                for (i, packet) in packets.enumerated() {
                    // Log UDP packets
                    if packet.count >= 20 && packet[9] == 17 {
                        let srcIP = "\(packet[12]).\(packet[13]).\(packet[14]).\(packet[15])"
                        let dstIP = "\(packet[16]).\(packet[17]).\(packet[18]).\(packet[19])"
                        let ihl = Int(packet[0] & 0x0F) * 4
                        var dstPort: UInt16 = 0
                        if packet.count >= ihl + 4 {
                            dstPort = UInt16(packet[ihl + 2]) << 8 | UInt16(packet[ihl + 3])
                        }
                        Logger.networkProtection.log("🦆 [Relay→WG] UDP: \(srcIP, privacy: .public) -> \(dstIP, privacy: .public):\(dstPort, privacy: .public)")
                    }

                    // Prepend 4-byte AF header for utun framing
                    let proto = protocols[i].uint32Value
                    var header = proto.bigEndian
                    var framedPacket = Data(bytes: &header, count: 4)
                    framedPacket.append(packet)

                    framedPacket.withUnsafeBytes { buf in
                        write(self.relayFd, buf.baseAddress, buf.count)
                    }
                }
                readLoop()
            }
        }
        readLoop()
    }

    // MARK: - Incoming (WireGuard → socketpair → packetFlow)

    private func startIncomingRelay(packetFlow: NEPacketTunnelFlow) {
        let source = DispatchSource.makeReadSource(fileDescriptor: relayFd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }

            var buf = [UInt8](repeating: 0, count: 65536)
            let bytesRead = read(self.relayFd, &buf, buf.count)
            guard bytesRead > 4 else { return }

            // Strip 4-byte AF header
            let proto = UInt32(buf[0]) << 24 | UInt32(buf[1]) << 16 | UInt32(buf[2]) << 8 | UInt32(buf[3])
            let packet = Data(buf[4..<bytesRead])

            packetFlow.writePackets([packet], withProtocols: [NSNumber(value: proto)])
        }
        source.resume()
        readSource = source
    }
}
