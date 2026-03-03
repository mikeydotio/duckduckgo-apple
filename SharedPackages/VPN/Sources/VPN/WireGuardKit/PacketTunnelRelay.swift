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

/// Bridges `NEPacketTunnelFlow` and WireGuard via direct CGo buffer passing.
///
/// Instead of a socketpair (PoC v1), Swift pushes packets directly into Go via
/// `wgReceivePacket` and Go pushes packets back via a registered callback.
/// This eliminates 4 syscalls per packet round-trip.
///
/// ```
/// OUTBOUND: packetFlow.readPackets() → wgReceivePacket [CGo] → Go channel → WireGuard encrypt
/// INBOUND:  WireGuard decrypt → tun.Write() → callback → packetFlow.writePackets()
/// ```
final class PacketTunnelRelay: TunnelFileDescriptorProviding {

    /// Function signature matching `wgReceivePacket(handle, buf, len) -> status`.
    typealias ReceivePacketFunc = (Int32, UnsafeRawPointer, Int32) -> Int32

    /// Function signature matching `wgSetPacketCallback(handle, context, callback)`.
    typealias SetPacketCallbackFunc = (Int32, UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32) -> Void)?) -> Void

    private var tunnelHandle: Int32 = -1
    private var isRunning = false
    private var packetFlowContext: Unmanaged<NEPacketTunnelFlow>?

    // MARK: - TunnelFileDescriptorProviding

    /// Returns a dummy fd. With ChannelTun, `wgTurnOn` ignores the fd parameter.
    func currentFileDescriptor() -> Int32? {
        return 0
    }

    // MARK: - Relay

    func start(packetFlow: NEPacketTunnelFlow,
               tunnelHandle: Int32,
               receivePacket: @escaping ReceivePacketFunc,
               setPacketCallback: @escaping SetPacketCallbackFunc) {
        self.tunnelHandle = tunnelHandle
        self.isRunning = true
        Logger.networkProtection.log("🦆 [Relay] Starting packet relay (channel mode, handle=\(tunnelHandle))")

        startIncomingRelay(packetFlow: packetFlow, tunnelHandle: tunnelHandle, setPacketCallback: setPacketCallback)
        startOutgoingRelay(packetFlow: packetFlow, tunnelHandle: tunnelHandle, receivePacket: receivePacket)
    }

    func stop() {
        isRunning = false
        tunnelHandle = -1
        packetFlowContext?.release()
        packetFlowContext = nil
    }

    // MARK: - Outgoing (packetFlow → wgReceivePacket → WireGuard)

    private func startOutgoingRelay(packetFlow: NEPacketTunnelFlow,
                                    tunnelHandle: Int32,
                                    receivePacket: @escaping ReceivePacketFunc) {
        func readLoop() {
            packetFlow.readPackets { [weak self] packets, _ in
                guard let self, self.isRunning else { return }

                for packet in packets {
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

                    // Push raw IP packet directly into Go (no AF header needed)
                    packet.withUnsafeBytes { buf in
                        guard let baseAddress = buf.baseAddress else { return }
                        _ = receivePacket(tunnelHandle, baseAddress, Int32(packet.count))
                    }
                }
                readLoop()
            }
        }
        readLoop()
    }

    // MARK: - Incoming (WireGuard → callback → packetFlow)

    private func startIncomingRelay(packetFlow: NEPacketTunnelFlow,
                                    tunnelHandle: Int32,
                                    setPacketCallback: @escaping SetPacketCallbackFunc) {
        // Retain the packetFlow in an opaque context so the C callback can reach it.
        let retained = Unmanaged.passRetained(packetFlow)
        packetFlowContext = retained
        let context = retained.toOpaque()

        setPacketCallback(tunnelHandle, context) { ctx, buf, len in
            guard let ctx, let buf, len > 0 else { return }

            let flow = Unmanaged<NEPacketTunnelFlow>.fromOpaque(ctx).takeUnretainedValue()
            let packet = Data(bytes: buf, count: Int(len))

            // Determine AF from IP version header
            let ipVersion = packet[0] >> 4
            let afNumber: UInt32 = (ipVersion == 6) ? UInt32(AF_INET6) : UInt32(AF_INET)

            flow.writePackets([packet], withProtocols: [NSNumber(value: afNumber)])
        }
    }
}
