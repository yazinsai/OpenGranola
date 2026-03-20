import Foundation

/// Auto-saves transcripts as plain text files to a configurable folder.
actor TranscriptLogger {
    private var directory: URL
    private var currentFile: URL?
    private var fileHandle: FileHandle?
    private var sessionHeader: String = ""
    private var hasReportedWriteError = false

    /// Called on the first write failure per session.
    var onWriteError: (@Sendable (String) -> Void)?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/OpenOats", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func updateDirectory(_ url: URL) {
        self.directory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func setWriteErrorHandler(_ handler: (@Sendable (String) -> Void)?) {
        onWriteError = handler
    }

    func startSession() {
        hasReportedWriteError = false
        let now = Date()
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy-MM-dd_HH-mm"
        let filename = "\(fileFmt.string(from: now)).txt"
        let file = directory.appendingPathComponent(filename)
        currentFile = file

        let headerFmt = DateFormatter()
        headerFmt.dateStyle = .medium
        headerFmt.timeStyle = .short
        sessionHeader = "OpenOats - \(headerFmt.string(from: now))\n\n"

        FileManager.default.createFile(atPath: file.path, contents: sessionHeader.data(using: .utf8))
        do {
            fileHandle = try FileHandle(forWritingTo: file)
            fileHandle?.seekToEndOfFile()
        } catch {
            reportWriteError("Failed to open transcript file: \(error.localizedDescription)")
        }
    }

    func append(speaker: String, text: String, timestamp: Date) {
        guard let fileHandle else {
            reportWriteError("Transcript logging interrupted: file is not writable.")
            return
        }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        let line = "[\(timeFmt.string(from: timestamp))] \(speaker): \(text)\n"
        if let data = line.data(using: .utf8) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        }
    }

    func endSession() {
        try? fileHandle?.close()
        fileHandle = nil
        currentFile = nil
    }

    private func reportWriteError(_ message: String) {
        diagLog("[TRANSCRIPT-LOGGER] \(message)")
        if !hasReportedWriteError {
            hasReportedWriteError = true
            onWriteError?(message)
        }
    }
}
