import Foundation
import DinoCraftCore
#if os(Windows)
import WinSDK
import ucrt
#endif

/// Crash capture on Windows. A double-clicked DinoCraft has no console, so Swift's "Fatal error"
/// message would vanish: error output goes to a file beside the log instead, and an unhandled
/// exception adds a marker, the exception code and where it happened. Next time, the launcher
/// finds it (`CrashReport`) and offers to send it.
enum WinCrash {
    #if os(Windows)
    nonisolated(unsafe) private static var file: HANDLE?
    #endif

    static func install(redirectErrors: Bool) {
        #if os(Windows)
        guard let log = Log.shared.currentLogURL else { return }
        let path = native(CrashReport.companion(of: log))
        // Error output (file descriptor 2, where Swift writes "Fatal error: ...") goes to the file
        // when there's no console window to show it.
        if redirectErrors {
            _ = path.withCString(encodedAs: UTF16.self) { name in
                "a".withCString(encodedAs: UTF16.self) { mode in _wfreopen(name, mode, __acrt_iob_func(2)) }
            }
        }
        // A second handle for the crash details, appending after whatever is already there.
        let handle: HANDLE? = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(FILE_APPEND_DATA), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil,
                        DWORD(OPEN_ALWAYS), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        if let handle, handle != INVALID_HANDLE_VALUE { file = handle }
        // Leave room to write the report even when the crash is a stack overflow.
        var guarantee: ULONG = 64 * 1024
        _ = SetThreadStackGuarantee(&guarantee)
        _ = SetUnhandledExceptionFilter { info in
            WinCrash.report(info)
            return 0   // EXCEPTION_CONTINUE_SEARCH: let Windows end the program as usual
        }
        #endif
    }

    #if os(Windows)
    private static func report(_ info: UnsafeMutablePointer<EXCEPTION_POINTERS>?) {
        var text = "\n*** DinoCraft crashed"
        if let record = info?.pointee.ExceptionRecord?.pointee {
            let code = record.ExceptionCode
            text += " - exception 0x" + String(code, radix: 16, uppercase: true)
            switch code {
            case 0xC0000005: text += " (access violation)"
            case 0xC00000FD: text += " (stack overflow)"
            case 0xC000001D, 0x80000003: text += " (Swift runtime check failed - see the Fatal error above)"
            case 0xC0000094: text += " (integer divide by zero)"
            default: break
            }
            text += " at " + where_(UInt(bitPattern: record.ExceptionAddress))
        }
        text += "\nBuild: \(BuildInfo.current.displayName)\nStack:\n"
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 48)
        let count = Int(RtlCaptureStackBackTrace(0, 48, &frames, nil))
        for frame in frames.prefix(count) {
            text += "  " + where_(UInt(bitPattern: frame)) + "\n"
        }
        let bytes = Array(text.utf8)
        if let file {
            var written: DWORD = 0
            _ = bytes.withUnsafeBufferPointer { WriteFile(file, $0.baseAddress, DWORD($0.count), &written, nil) }
            _ = FlushFileBuffers(file)
        }
    }

    /// "DinoCraft.exe+0x1a2b3c" for an address inside a loaded program or library.
    private static func where_(_ address: UInt) -> String {
        let hex = "0x" + String(address, radix: 16)
        var module: HMODULE?
        // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT
        guard address != 0, GetModuleHandleExW(DWORD(6), UnsafePointer<WCHAR>(bitPattern: address), &module),
              let module else { return hex }
        var name = [WCHAR](repeating: 0, count: 260)
        let length = Int(GetModuleFileNameW(module, &name, DWORD(name.count)))
        let path = String(decoding: name.prefix(length), as: UTF16.self)
        let short = path.split(separator: "\\").last.map(String.init) ?? path
        return "\(short)+0x" + String(address &- UInt(bitPattern: module), radix: 16)
    }

    private static func native(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }
    #endif
}
