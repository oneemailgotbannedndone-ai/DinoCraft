import Foundation
import DinoCraftCore

/// Installs a downloaded update on Windows. A running program can't overwrite itself, so this unzips the
/// new version, then starts a small script that waits for DinoCraft to close, copies the new files over
/// the old ones and starts the new version. Worlds and settings live elsewhere, so they're untouched.
enum WinUpdater {
    /// Returns an error message, or nil when the update is ready and DinoCraft should now quit.
    static func install(zip: URL) -> String? {
        #if os(Windows)
        let fm = FileManager.default
        guard let exe = Bundle.main.executableURL else { return "Couldn't find where DinoCraft is installed." }
        let installDir = exe.deletingLastPathComponent()
        let unpacked = zip.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
        try? fm.removeItem(at: unpacked)
        do {
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        } catch {
            return "Couldn't prepare the update: \(error.localizedDescription)"
        }
        // Windows 10 and 11 include tar, which also unpacks zip files.
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\tar.exe")
        tar.arguments = ["-xf", native(zip), "-C", native(unpacked)]
        do {
            try tar.run()
            tar.waitUntilExit()
        } catch {
            return "Couldn't unpack the update: \(error.localizedDescription)"
        }
        guard tar.terminationStatus == 0, let source = folderWithGame(in: unpacked) else {
            return "The update download was damaged. Try again."
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        @echo off
        title Updating DinoCraft
        echo Updating DinoCraft, please wait...
        :wait
        tasklist /FI "PID eq \(pid)" 2>nul | find "\(pid)" >nul
        if not errorlevel 1 (
          timeout /t 1 /nobreak >nul
          goto wait
        )
        robocopy "\(native(source))" "\(native(installDir))" /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP >nul
        start "" "\(native(installDir))\\DinoCraft.exe"
        del "%~f0"

        """
        let scriptURL = zip.deletingLastPathComponent().appendingPathComponent("update.bat")
        do {
            try script.replacingOccurrences(of: "\n", with: "\r\n").write(to: scriptURL, atomically: true, encoding: .utf8)
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
            runner.arguments = ["/c", native(scriptURL)]
            try runner.run()
        } catch {
            return "Couldn't start the updater: \(error.localizedDescription)"
        }
        Log.info("Update ready: \(native(source)) → \(native(installDir))", category: "Update")
        return nil
        #else
        return "Updating is only available in the Windows and Mac versions."
        #endif
    }

    /// The folder that holds DinoCraft.exe (the zip may or may not have a top-level folder).
    private static func folderWithGame(in dir: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("DinoCraft.exe").path) { return dir }
        for sub in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            if fm.fileExists(atPath: sub.appendingPathComponent("DinoCraft.exe").path) { return sub }
        }
        return nil
    }

    /// A path in Windows' own form (C:\Users\...).
    private static func native(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }
}
