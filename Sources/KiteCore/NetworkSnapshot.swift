import Darwin
import Foundation

public struct PortSnapshot: Identifiable, Equatable, Sendable {
    public enum Transport: String, Sendable {
        case tcp = "TCP"
        case udp = "UDP"
    }

    public let pid: Int32
    public let descriptor: Int32
    public let processName: String
    public let transport: Transport
    public let localAddress: String
    public let localPort: Int
    public let remoteAddress: String?
    public let remotePort: Int?
    public let state: String?

    public init(
        pid: Int32,
        descriptor: Int32,
        processName: String,
        transport: Transport,
        localAddress: String,
        localPort: Int,
        remoteAddress: String? = nil,
        remotePort: Int? = nil,
        state: String? = nil
        ) {
        self.pid = pid
        self.descriptor = descriptor
        self.processName = processName
        self.transport = transport
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.state = state
    }

    public var id: String { "\(pid)/\(descriptor)" }
}

public protocol PortProvider: Sendable {
    func snapshot() throws -> [PortSnapshot]
}

public enum PortProviderError: Error, Equatable {
    case processListUnavailable
}

public struct MacOSPortProvider: PortProvider {
    public init() {}

    public func snapshot() throws -> [PortSnapshot] {
        let byteCount = proc_listallpids(nil, 0)
        guard byteCount > 0 else { throw PortProviderError.processListUnavailable }

        var pids = [Int32](repeating: 0, count: Int(byteCount) + 32)
        let pidBytes = Int32(pids.count * MemoryLayout<Int32>.stride)
        let result = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, pidBytes)
        }
        guard result > 0 else { throw PortProviderError.processListUnavailable }

        var ports: [PortSnapshot] = []
        for pid in Set(pids.prefix(Int(result))) where pid > 0 {
            ports.append(contentsOf: readPorts(pid: pid))
        }
        return ports.sorted {
            $0.localPort != $1.localPort ? $0.localPort < $1.localPort : ($0.pid, $0.transport.rawValue) < ($1.pid, $1.transport.rawValue)
        }
    }

    private func readPorts(pid: Int32) -> [PortSnapshot] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride)
        let written = fds.withUnsafeMutableBufferPointer {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, bufferSize)
        }
        guard written > 0 else { return [] }

        let name = processName(pid)
        var ports: [PortSnapshot] = []
        for index in 0..<(Int(written) / MemoryLayout<proc_fdinfo>.stride) where fds[index].proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.stride)
            guard proc_pidfdinfo(pid, fds[index].proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size else { continue }
            let socket = info.psi
            guard socket.soi_family == AF_INET || socket.soi_family == AF_INET6 else { continue }
            let transport: PortSnapshot.Transport
            switch socket.soi_protocol {
            case IPPROTO_TCP: transport = .tcp
            case IPPROTO_UDP: transport = .udp
            default: continue
            }

            let endpoint = transport == .tcp ? socket.soi_proto.pri_tcp.tcpsi_ini : socket.soi_proto.pri_in
            let localPort = Int(UInt16(truncatingIfNeeded: endpoint.insi_lport).bigEndian)
            let remotePort = Int(UInt16(truncatingIfNeeded: endpoint.insi_fport).bigEndian)
            let localBytes = withUnsafeBytes(of: endpoint.insi_laddr.ina_46) { Array($0) }
            let remoteBytes = withUnsafeBytes(of: endpoint.insi_faddr.ina_46) { Array($0) }
            // INSI_IPV4 (0x01) marks IPv4-mapped endpoints on AF_INET6 sockets.
            let isIPv4 = socket.soi_family == AF_INET || endpoint.insi_vflag & 0x01 != 0
            let hasRemote = remotePort > 0 && (transport == .udp || tcpState(socket.soi_proto.pri_tcp.tcpsi_state) != .listen)

            ports.append(
                PortSnapshot(
                    pid: pid,
                    descriptor: fds[index].proc_fd,
                    processName: name,
                    transport: transport,
                    localAddress: formatAddress(localBytes, isIPv4: isIPv4),
                    localPort: localPort,
                    remoteAddress: hasRemote ? formatAddress(remoteBytes, isIPv4: isIPv4) : nil,
                    remotePort: hasRemote ? remotePort : nil,
                    state: transport == .tcp ? tcpStateName(socket.soi_proto.pri_tcp.tcpsi_state) : nil
                )
            )
        }
        return ports
    }

    private enum TCPState {
        case closed, listen, synSent, synReceived, established, closeWait, finWait1, closing, lastAck, finWait2, timeWait
    }

    private func tcpState(_ raw: Int32) -> TCPState {
        switch raw {
        case TCPS_LISTEN: .listen
        case TCPS_SYN_SENT: .synSent
        case TCPS_SYN_RECEIVED: .synReceived
        case TCPS_ESTABLISHED: .established
        case TCPS_CLOSE_WAIT: .closeWait
        case TCPS_FIN_WAIT_1: .finWait1
        case TCPS_CLOSING: .closing
        case TCPS_LAST_ACK: .lastAck
        case TCPS_FIN_WAIT_2: .finWait2
        case TCPS_TIME_WAIT: .timeWait
        default: .closed
        }
    }

    private func tcpStateName(_ raw: Int32) -> String {
        switch tcpState(raw) {
        case .closed: "Closed"
        case .listen: "Listen"
        case .synSent: "SYN Sent"
        case .synReceived: "SYN Received"
        case .established: "Established"
        case .closeWait: "Close Wait"
        case .finWait1: "FIN Wait 1"
        case .closing: "Closing"
        case .lastAck: "Last ACK"
        case .finWait2: "FIN Wait 2"
        case .timeWait: "Time Wait"
        }
    }

    private func formatAddress(_ bytes: [UInt8], isIPv4: Bool) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result: Bool
        if isIPv4 {
            var addr = in_addr(s_addr: bytes.suffix(4).reduce(0) { $0 << 8 | UInt32($1) }.bigEndian)
            result = withUnsafePointer(to: &addr) { pointer in
                inet_ntop(AF_INET, UnsafeRawPointer(pointer), &buffer, socklen_t(buffer.count)) != nil
            }
        } else {
            var addr = in6_addr()
            withUnsafeMutableBytes(of: &addr) { destination in
                destination.copyBytes(from: bytes.prefix(16))
            }
            result = withUnsafePointer(to: &addr) { pointer in
                inet_ntop(AF_INET6, UnsafeRawPointer(pointer), &buffer, socklen_t(buffer.count)) != nil
            }
        }
        guard result else { return "?" }
        return cString(buffer)
    }

    private func cString(_ value: [CChar]) -> String {
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = buffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return "Process \(pid)" }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
