import Foundation

/// Auto-saves transcripts as plain text files to a configurable folder.
actor TranscriptLogger {
    private var directory: URL
    private var currentFile: URL?
    private var fileHandle: FileHandle?
    private var sessionHeader: String = ""

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/OpenOats", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func updateDirectory(_ url: URL) {
        self.directory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func startSession() {
        let now = Date()
        let fileFmt = DateFormatter()
        fileFmt.dateFormat = "yyyy-MM-dd_HH-mm"
        let filename = "\(fileFmt.string(from: now)).txt"
        currentFile = directory.appendingPathComponent(filename)

        let headerFmt = DateFormatter()
        headerFmt.dateStyle = .medium
        headerFmt.timeStyle = .short
        sessionHeader = "OpenOats - \(headerFmt.string(from: now))\n\n"

        FileManager.default.createFile(atPath: currentFile!.path, contents: sessionHeader.data(using: .utf8))
        fileHandle = try? FileHandle(forWritingTo: currentFile!)
        fileHandle?.seekToEndOfFile()
    }

    func append(speaker: String, text: String, timestamp: Date) {
        guard let fileHandle else { return }
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
}
