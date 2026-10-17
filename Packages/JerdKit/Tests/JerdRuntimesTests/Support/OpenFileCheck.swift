import Darwin
import Foundation

/// True while this test process has `url` open, for example while a hash reads it.
///
/// It compares the device and inode of each open vnode, so a `/var` and `/private/var` path match.
func isOpenInThisProcess(_ url: URL) -> Bool {
    var target = stat()
    guard stat(url.path, &target) == 0 else { return false }
    return openDescriptors().contains { descriptor in
        guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return false }
        var info = vnode_fdinfowithpath()
        let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        guard proc_pidfdinfo(getpid(), descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else {
            return false
        }
        let file = info.pvip.vip_vi.vi_stat
        return file.vst_ino == target.st_ino && file.vst_dev == target.st_dev
    }
}

/// The open descriptors of this process.
private func openDescriptors() -> [proc_fdinfo] {
    let needed = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
    guard needed > 0 else { return [] }
    let stride = MemoryLayout<proc_fdinfo>.stride
    // Room for descriptors that open between the two calls.
    var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 32)
    let filled = descriptors.withUnsafeMutableBytes { buffer in
        proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
    }
    return Array(descriptors.prefix(max(0, Int(filled) / stride)))
}
