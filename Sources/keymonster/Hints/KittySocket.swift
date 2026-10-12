import Darwin
import Foundation

/// Finds the socket a running kitty is listening on for remote control, by
/// asking the process itself rather than guessing from its config. The config
/// is a poor oracle — `include`d files, `--override` and `--listen-on` on the
/// command line, `KITTY_CONFIG_DIRECTORY`, and the `{kitty_pid}` placeholder
/// all change the answer — while the kernel knows exactly which unix sockets
/// the process is listening on.
enum KittySocket {
    /// A unix-domain socket a process holds open.
    struct Candidate: Equatable {
        let path: String
        let isListening: Bool
    }

    /// The path kitty uses for `listen_on unix:/tmp/kitty`: it appends the pid.
    /// Only a fallback for when the process can't be inspected.
    static func conventionalPath(pid: pid_t) -> String { "/tmp/kitty-\(pid)" }

    /// The listening socket to talk to, from what the process holds open.
    /// Pure: `exists` is injected so the choice is testable. Prefers a socket
    /// that looks like kitty's own when a process listens on several.
    static func choose(
        from candidates: [Candidate], pid: pid_t, exists: (String) -> Bool
    ) -> String? {
        let listening = candidates.filter(\.isListening).map(\.path).filter(exists)
        if let kitty = listening.first(where: { $0.contains("kitty") }) { return kitty }
        if let any = listening.first { return any }
        let fallback = conventionalPath(pid: pid)
        return exists(fallback) ? fallback : nil
    }

    static func discover(pid: pid_t) -> String? {
        choose(
            from: unixSockets(of: pid), pid: pid,
            exists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    /// Every unix-domain socket `pid` has open, via libproc — the same data
    /// `lsof -U` prints, without spawning a process. Empty if the process can't
    /// be inspected.
    static func unixSockets(of pid: pid_t) -> [Candidate] {
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return [] }
        var descriptors = [proc_fdinfo](
            repeating: proc_fdinfo(), count: Int(listSize) / MemoryLayout<proc_fdinfo>.stride
        )
        let filled = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, listSize)
        }
        guard filled > 0 else { return [] }

        var found: [Candidate] = []
        for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == Int32(SOCKINFO_UN) else { continue }
            let path = withUnsafeBytes(of: info.psi.soi_proto.pri_un.unsi_addr.ua_sun.sun_path) {
                String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8)
            }
            guard let path, !path.isEmpty else { continue }
            found.append(Candidate(
                path: path, isListening: info.psi.soi_options & Int16(SO_ACCEPTCONN) != 0
            ))
        }
        return found
    }
}
