import Foundation
import Darwin

/// Reads the main thread's call stack from another thread: suspend it, read its registers,
/// walk the frame-pointer chain, resume.
///
/// The one rule that matters: NOTHING may allocate while the thread is suspended — it may be
/// holding the malloc lock, and a sampler that mallocs then deadlocks the very app it is
/// watching. The walk writes into a buffer allocated beforehand and reads stack memory through
/// `vm_read_overwrite` (a bad pointer returns an error instead of crashing); symbolication
/// happens only after `thread_resume`. arm64 only; other architectures sample nothing.
public enum MainThreadSampler {
    nonisolated(unsafe) private static var mainThread: thread_act_t = 0

    /// Call ON the main thread once; `mach_thread_self` names the calling thread.
    public static func captureMainThreadIdentity() {
        precondition(Thread.isMainThread, "captureMainThreadIdentity must run on the main thread")
        mainThread = mach_thread_self()
    }

    /// Return addresses, innermost first (PC, then LR, then the frame chain). Empty when the
    /// identity was never captured or the thread cannot be read.
    public static func sample(maxFrames: Int = 48) -> [UInt] {
        #if arch(arm64)
        guard mainThread != 0 else { return [] }
        let buf = UnsafeMutablePointer<UInt>.allocate(capacity: maxFrames)
        defer { buf.deallocate() }
        var n = 0
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let mask: UInt = 0x0000_7FFF_FFFF_FFFF   // strip pointer-authentication bits
            buf[n] = UInt(state.__pc) & mask; n += 1
            buf[n] = UInt(state.__lr) & mask; n += 1
            var fp = UInt(state.__fp) & mask
            while n < maxFrames, fp != 0 {
                var pair: (UInt, UInt) = (0, 0)
                var got: vm_size_t = 0
                let r = withUnsafeMutablePointer(to: &pair) {
                    vm_read_overwrite(mach_task_self_, vm_address_t(fp), 16, vm_address_t(UInt(bitPattern: $0)), &got)
                }
                guard r == KERN_SUCCESS, got == 16 else { break }
                let ret = pair.1 & mask
                guard ret != 0 else { break }
                buf[n] = ret; n += 1
                let next = pair.0 & mask
                guard next > fp else { break }   // frames only ever go UP the stack
                fp = next
            }
        }
        thread_resume(mainThread)
        return Array(UnsafeBufferPointer(start: buf, count: n))
        #else
        return []
        #endif
    }

    /// "image  symbol + offset" per frame, Swift names demangled.
    public static func symbolicate(_ frames: [UInt]) -> [String] {
        frames.map { addr in
            var info = Dl_info()
            guard let p = UnsafeRawPointer(bitPattern: addr), dladdr(p, &info) != 0 else {
                return String(format: "0x%lx", addr)
            }
            let image = info.dli_fname.map { String(cString: $0).split(separator: "/").last.map(String.init) ?? "" } ?? "?"
            let sym = info.dli_sname.map { demangle(String(cString: $0)) } ?? String(format: "0x%lx", addr)
            let off = info.dli_saddr.map { addr &- UInt(bitPattern: $0) } ?? 0
            return "\(image)  \(sym) + \(off)"
        }
    }

    @_silgen_name("swift_demangle")
    private static func swiftDemangle(_ name: UnsafePointer<CChar>?, _ length: Int, _ out: UnsafeMutablePointer<CChar>?,
                                      _ outSize: UnsafeMutablePointer<Int>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

    /// A Swift-mangled symbol as source would write it; anything else unchanged.
    public static func demangle(_ s: String) -> String {
        guard s.hasPrefix("$s") || s.hasPrefix("_$s") || s.hasPrefix("$S") else { return s }
        guard let p = s.withCString({ swiftDemangle($0, strlen($0), nil, nil, 0) }) else { return s }
        defer { free(p) }
        return String(cString: p)
    }
}
