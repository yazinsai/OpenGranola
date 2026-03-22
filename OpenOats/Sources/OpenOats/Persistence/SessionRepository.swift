import Foundation

typealias SessionSummary = SessionIndex

struct SessionHandle: Sendable, Equatable {
    let id: String
}

struct SessionStartConfig: Sendable {
    var startedAt: Date = .now
    var templateSnapshot: TemplateSnapshot?
    var title: String?
    var meetingApp: String?
    var engine: String?
}

struct SessionFinalizeMetadata: Sendable {
    let endedAt: Date
    let title: String?
    let meetingApp: String?
    let engine: String?
}

struct LiveUtteranceMetadata: Sendable {
    let suggestions: [String]?
    let kbHits: [String]?
    let suggestionDecision: SuggestionDecision?
    let surfacedSuggestionText: String?
    let conversationStateSummary: String?
    let refinedText: String?

    static let empty = LiveUtteranceMetadata(
        suggestions: nil,
        kbHits: nil,
        suggestionDecision: nil,
        surfacedSuggestionText: nil,
        conversationStateSummary: nil,
        refinedText: nil
    )
}

struct SessionDetail: Sendable {
    let summary: SessionSummary
    let liveTranscript: [SessionRecord]
    let finalTranscript: [SessionRecord]?
    let notes: EnhancedNotes?

    var transcript: [SessionRecord] {
        finalTranscript ?? liveTranscript
    }
}

actor SessionRepository {
    private struct StoredSessionMetadata: Codable, Sendable {
        var summary: SessionSummary
        var notesTemplate: TemplateSnapshot?
        var notesGeneratedAt: Date?
    }

    private let baseDirectory: URL
    private let sessionsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootDirectory: URL? = nil) {
        let resolvedBaseDirectory: URL
        if let rootDirectory {
            resolvedBaseDirectory = rootDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            resolvedBaseDirectory = appSupport.appendingPathComponent("OpenOats", isDirectory: true)
        }

        self.baseDirectory = resolvedBaseDirectory
        self.sessionsDirectory = resolvedBaseDirectory.appendingPathComponent("sessions", isDirectory: true)
        self.encoder = JSONEncoder.iso8601Encoder
        self.decoder = JSONDecoder.iso8601Decoder

        try? FileManager.default.createDirectory(
            at: sessionsDirectory,
            withIntermediateDirectories: true
        )
        Self.dropMetadataNeverIndex(in: sessionsDirectory)
        Self.cleanupOrphanedBatchAudio(in: sessionsDirectory)
    }

    func listSessions() -> [SessionSummary] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        var summariesByID: [String: SessionSummary] = [:]

        for item in contents {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey]) else { continue }
            if values.isDirectory == true,
               let summary = loadCanonicalSummaryIfPresent(sessionID: item.lastPathComponent) {
                summariesByID[summary.id] = summary
            }
        }

        for item in contents where item.pathExtension == "jsonl" || item.lastPathComponent.hasSuffix(".meta.json") {
            let sessionID: String
            if item.pathExtension == "jsonl" {
                sessionID = item.deletingPathExtension().lastPathComponent
            } else {
                sessionID = String(item.lastPathComponent.dropLast(".meta.json".count))
            }

            guard summariesByID[sessionID] == nil else { continue }
            if let summary = loadLegacySummary(sessionID: sessionID) {
                summariesByID[sessionID] = summary
            }
        }

        return summariesByID.values.sorted { $0.startedAt > $1.startedAt }
    }

    func loadSession(id: String) -> SessionDetail {
        if let canonical = loadCanonicalSession(sessionID: id) {
            return canonical
        }

        return loadLegacySession(sessionID: id)
            ?? SessionDetail(summary: SessionSummary(
                id: id,
                startedAt: .now,
                endedAt: nil,
                templateSnapshot: nil,
                title: nil,
                utteranceCount: 0,
                hasNotes: false,
                meetingApp: nil,
                engine: nil
            ), liveTranscript: [], finalTranscript: nil, notes: nil)
    }

    func startSession(config: SessionStartConfig) -> SessionHandle {
        let sessionID = makeSessionID(for: config.startedAt)
        let sessionDirectory = canonicalSessionDirectory(for: sessionID)
        let audioDirectory = sessionAudioDirectory(for: sessionID)

        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let summary = SessionSummary(
            id: sessionID,
            startedAt: config.startedAt,
            endedAt: nil,
            templateSnapshot: config.templateSnapshot,
            title: config.title,
            utteranceCount: 0,
            hasNotes: false,
            meetingApp: config.meetingApp,
            engine: config.engine
        )

        let metadata = StoredSessionMetadata(
            summary: summary,
            notesTemplate: nil,
            notesGeneratedAt: nil
        )

        writeSessionMetadata(metadata, to: sessionDirectory)
        ensureFileExists(at: liveTranscriptURL(for: sessionID))

        return SessionHandle(id: sessionID)
    }

    func appendLiveUtterance(
        sessionID: String,
        utterance: Utterance,
        metadata: LiveUtteranceMetadata = .empty
    ) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let record = SessionRecord(
            speaker: utterance.speaker,
            text: utterance.text,
            timestamp: utterance.timestamp,
            suggestions: metadata.suggestions,
            kbHits: metadata.kbHits,
            suggestionDecision: metadata.suggestionDecision,
            surfacedSuggestionText: metadata.surfacedSuggestionText,
            conversationStateSummary: metadata.conversationStateSummary,
            refinedText: metadata.refinedText ?? utterance.refinedText
        )
        appendRecord(record, to: liveTranscriptURL(for: sessionID))
    }

    func finalizeSession(sessionID: String, finalMetadata: SessionFinalizeMetadata) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        guard var metadata = loadStoredSessionMetadata(sessionID: sessionID) else { return }

        let liveCount = loadJSONL(from: liveTranscriptURL(for: sessionID)).count
        metadata.summary = SessionSummary(
            id: metadata.summary.id,
            startedAt: metadata.summary.startedAt,
            endedAt: finalMetadata.endedAt,
            templateSnapshot: metadata.summary.templateSnapshot,
            title: finalMetadata.title,
            utteranceCount: liveCount,
            hasNotes: metadata.summary.hasNotes,
            meetingApp: finalMetadata.meetingApp,
            engine: finalMetadata.engine
        )
        writeSessionMetadata(metadata, to: canonicalSessionDirectory(for: sessionID))
    }

    func saveFinalTranscript(sessionID: String, records: [SessionRecord]) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        writeJSONL(records, to: finalTranscriptURL(for: sessionID))
    }

    func saveNotes(sessionID: String, notes: EnhancedNotes) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let sessionDirectory = canonicalSessionDirectory(for: sessionID)
        try? notes.markdown.write(
            to: notesMarkdownURL(for: sessionID),
            atomically: true,
            encoding: .utf8
        )

        guard var metadata = loadStoredSessionMetadata(sessionID: sessionID) else { return }
        metadata.summary = SessionSummary(
            id: metadata.summary.id,
            startedAt: metadata.summary.startedAt,
            endedAt: metadata.summary.endedAt,
            templateSnapshot: metadata.summary.templateSnapshot,
            title: metadata.summary.title,
            utteranceCount: metadata.summary.utteranceCount,
            hasNotes: true,
            meetingApp: metadata.summary.meetingApp,
            engine: metadata.summary.engine
        )
        metadata.notesTemplate = notes.template
        metadata.notesGeneratedAt = notes.generatedAt
        writeSessionMetadata(metadata, to: sessionDirectory)
    }

    func renameSession(sessionID: String, title: String) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        guard var metadata = loadStoredSessionMetadata(sessionID: sessionID) else { return }
        metadata.summary = SessionSummary(
            id: metadata.summary.id,
            startedAt: metadata.summary.startedAt,
            endedAt: metadata.summary.endedAt,
            templateSnapshot: metadata.summary.templateSnapshot,
            title: title.isEmpty ? nil : title,
            utteranceCount: metadata.summary.utteranceCount,
            hasNotes: metadata.summary.hasNotes,
            meetingApp: metadata.summary.meetingApp,
            engine: metadata.summary.engine
        )
        writeSessionMetadata(metadata, to: canonicalSessionDirectory(for: sessionID))
    }

    func deleteSession(sessionID: String) {
        let fm = FileManager.default

        let canonicalDirectory = canonicalSessionDirectory(for: sessionID)
        if fm.fileExists(atPath: canonicalDirectory.path) {
            try? fm.removeItem(at: canonicalDirectory)
        }

        let legacyLive = legacyLiveTranscriptURL(for: sessionID)
        let legacyMeta = legacySidecarURL(for: sessionID)
        let legacyBatchDirectory = legacyBatchDirectory(for: sessionID)
        if fm.fileExists(atPath: legacyLive.path) {
            try? fm.removeItem(at: legacyLive)
        }
        if fm.fileExists(atPath: legacyMeta.path) {
            try? fm.removeItem(at: legacyMeta)
        }
        if fm.fileExists(atPath: legacyBatchDirectory.path) {
            try? fm.removeItem(at: legacyBatchDirectory)
        }
    }

    func exportPlainText(sessionID: String) -> String {
        let detail = loadSession(id: sessionID)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return detail.transcript.map { record in
            let text = record.refinedText ?? record.text
            return "[\(formatter.string(from: record.timestamp))] \(record.speaker.displayLabel): \(text)"
        }.joined(separator: "\n")
    }

    func audioDirectory(for sessionID: String) -> URL {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let url = sessionAudioDirectory(for: sessionID)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func batchAudioURLs(sessionID: String) -> (mic: URL?, sys: URL?) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let fm = FileManager.default
        let audioDirectory = sessionAudioDirectory(for: sessionID)
        let micURL = audioDirectory.appendingPathComponent("mic.caf")
        let sysURL = audioDirectory.appendingPathComponent("sys.caf")
        return (
            mic: fm.fileExists(atPath: micURL.path) ? micURL : nil,
            sys: fm.fileExists(atPath: sysURL.path) ? sysURL : nil
        )
    }

    func stashAudioForBatch(
        sessionID: String,
        micURL: URL?,
        sysURL: URL?,
        anchors: BatchAnchors
    ) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let fm = FileManager.default
        let audioDirectory = sessionAudioDirectory(for: sessionID)
        try? fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        if let micURL, fm.fileExists(atPath: micURL.path) {
            let destination = audioDirectory.appendingPathComponent("mic.caf")
            try? fm.removeItem(at: destination)
            try? fm.moveItem(at: micURL, to: destination)
        }

        if let sysURL, fm.fileExists(atPath: sysURL.path) {
            let destination = audioDirectory.appendingPathComponent("sys.caf")
            try? fm.removeItem(at: destination)
            try? fm.moveItem(at: sysURL, to: destination)
        }

        let meta = BatchMeta(
            micStartDate: anchors.micStartDate,
            sysStartDate: anchors.sysStartDate,
            micAnchors: anchors.micAnchors.map { .init(frame: $0.frame, date: $0.date) },
            sysAnchors: anchors.sysAnchors.map { .init(frame: $0.frame, date: $0.date) }
        )
        if let data = try? encoder.encode(meta) {
            try? data.write(
                to: audioDirectory.appendingPathComponent("batch-meta.json"),
                options: .atomic
            )
        }
    }

    func cleanupBatchAudio(sessionID: String) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let fm = FileManager.default
        let audioDirectory = sessionAudioDirectory(for: sessionID)
        try? fm.removeItem(at: audioDirectory.appendingPathComponent("mic.caf"))
        try? fm.removeItem(at: audioDirectory.appendingPathComponent("sys.caf"))
        try? fm.removeItem(at: audioDirectory.appendingPathComponent("batch-meta.json"))
    }

    func loadBatchMeta(sessionID: String) -> BatchMeta? {
        ensureCanonicalSessionImported(sessionID: sessionID)
        let metaURL = sessionAudioDirectory(for: sessionID).appendingPathComponent("batch-meta.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? decoder.decode(BatchMeta.self, from: data)
    }

    func backfillRefinedText(sessionID: String, from utterances: [Utterance]) {
        ensureCanonicalSessionImported(sessionID: sessionID)
        rewriteJSONLWithRefinedText(file: liveTranscriptURL(for: sessionID), utterances: utterances)
    }

    func seedSession(
        id: String,
        records: [SessionRecord],
        startedAt: Date,
        endedAt: Date? = nil,
        templateSnapshot: TemplateSnapshot? = nil,
        title: String? = nil,
        notes: EnhancedNotes? = nil
    ) {
        let sessionDirectory = canonicalSessionDirectory(for: id)
        try? FileManager.default.createDirectory(
            at: sessionAudioDirectory(for: id),
            withIntermediateDirectories: true
        )

        writeJSONL(records, to: liveTranscriptURL(for: id))
        if let notes {
            try? notes.markdown.write(
                to: notesMarkdownURL(for: id),
                atomically: true,
                encoding: .utf8
            )
        }

        let metadata = StoredSessionMetadata(
            summary: SessionSummary(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                templateSnapshot: templateSnapshot,
                title: title,
                utteranceCount: records.count,
                hasNotes: notes != nil,
                meetingApp: nil,
                engine: nil
            ),
            notesTemplate: notes?.template,
            notesGeneratedAt: notes?.generatedAt
        )
        writeSessionMetadata(metadata, to: sessionDirectory)
    }

    // MARK: - Private

    private static func dropMetadataNeverIndex(in directory: URL) {
        let sentinel = directory.appendingPathComponent(".metadata_never_index")
        if !FileManager.default.fileExists(atPath: sentinel.path) {
            FileManager.default.createFile(atPath: sentinel.path, contents: nil)
        }
    }

    private static func cleanupOrphanedBatchAudio(in sessionsDirectory: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-24 * 3600)

        for item in contents {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  values.isDirectory == true else {
                continue
            }

            let name = item.lastPathComponent
            guard name.hasPrefix("session_") else { continue }

            let audioDirectory = item.appendingPathComponent("audio", isDirectory: true)
            let micURL = audioDirectory.appendingPathComponent("mic.caf")
            let sysURL = audioDirectory.appendingPathComponent("sys.caf")

            let hasMic = fm.fileExists(atPath: micURL.path)
            let hasSys = fm.fileExists(atPath: sysURL.path)
            guard hasMic || hasSys else { continue }

            if let modificationDate = values.contentModificationDate, modificationDate < cutoff {
                try? fm.removeItem(at: micURL)
                try? fm.removeItem(at: sysURL)
                try? fm.removeItem(at: audioDirectory.appendingPathComponent("batch-meta.json"))
            }
        }
    }

    private func canonicalSessionDirectory(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
    }

    private func sessionAudioDirectory(for sessionID: String) -> URL {
        canonicalSessionDirectory(for: sessionID).appendingPathComponent("audio", isDirectory: true)
    }

    private func sessionMetadataURL(for sessionID: String) -> URL {
        canonicalSessionDirectory(for: sessionID).appendingPathComponent("session.json")
    }

    private func liveTranscriptURL(for sessionID: String) -> URL {
        canonicalSessionDirectory(for: sessionID).appendingPathComponent("transcript.live.jsonl")
    }

    private func finalTranscriptURL(for sessionID: String) -> URL {
        canonicalSessionDirectory(for: sessionID).appendingPathComponent("transcript.final.jsonl")
    }

    private func notesMarkdownURL(for sessionID: String) -> URL {
        canonicalSessionDirectory(for: sessionID).appendingPathComponent("notes.md")
    }

    private func legacyLiveTranscriptURL(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionID).jsonl")
    }

    private func legacySidecarURL(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionID).meta.json")
    }

    private func legacyBatchDirectory(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
    }

    private func ensureFileExists(at url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    private func loadStoredSessionMetadata(sessionID: String) -> StoredSessionMetadata? {
        let url = sessionMetadataURL(for: sessionID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(StoredSessionMetadata.self, from: data)
    }

    private func writeSessionMetadata(_ metadata: StoredSessionMetadata, to sessionDirectory: URL) {
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(metadata) else { return }
        let metadataURL = sessionDirectory.appendingPathComponent("session.json")
        try? data.write(to: metadataURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: metadataURL.path
        )
    }

    private func appendRecord(_ record: SessionRecord, to url: URL) {
        ensureFileExists(at: url)
        guard let data = try? encoder.encode(record) else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.write(contentsOf: Data("\n".utf8))
    }

    private func loadJSONL(from url: URL) -> [SessionRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(SessionRecord.self, from: data)
            }
    }

    private func writeJSONL(_ records: [SessionRecord], to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var payload = Data()
        for record in records {
            if let data = try? encoder.encode(record) {
                payload.append(data)
                payload.append(Data("\n".utf8))
            }
        }
        try? payload.write(to: url, options: .atomic)
    }

    private func loadCanonicalSummaryIfPresent(sessionID: String) -> SessionSummary? {
        loadStoredSessionMetadata(sessionID: sessionID)?.summary
    }

    private func loadCanonicalSession(sessionID: String) -> SessionDetail? {
        guard let metadata = loadStoredSessionMetadata(sessionID: sessionID) else { return nil }

        let liveTranscript = loadJSONL(from: liveTranscriptURL(for: sessionID))
        let finalTranscript = FileManager.default.fileExists(atPath: finalTranscriptURL(for: sessionID).path)
            ? loadJSONL(from: finalTranscriptURL(for: sessionID))
            : nil

        let notes: EnhancedNotes?
        if let markdown = try? String(contentsOf: notesMarkdownURL(for: sessionID), encoding: .utf8),
           let template = metadata.notesTemplate,
           let generatedAt = metadata.notesGeneratedAt {
            notes = EnhancedNotes(template: template, generatedAt: generatedAt, markdown: markdown)
        } else {
            notes = nil
        }

        return SessionDetail(
            summary: metadata.summary,
            liveTranscript: liveTranscript,
            finalTranscript: finalTranscript?.isEmpty == false ? finalTranscript : nil,
            notes: notes
        )
    }

    private func loadLegacySummary(sessionID: String) -> SessionSummary? {
        let sidecarURL = legacySidecarURL(for: sessionID)
        if let data = try? Data(contentsOf: sidecarURL),
           let sidecar = try? decoder.decode(SessionSidecar.self, from: data) {
            return sidecar.index
        }

        let liveURL = legacyLiveTranscriptURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: liveURL.path) else { return nil }

        let datePart = sessionID.replacingOccurrences(of: "session_", with: "")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let startedAt = formatter.date(from: datePart) ?? .now
        let utteranceCount = loadJSONL(from: liveURL).count

        return SessionSummary(
            id: sessionID,
            startedAt: startedAt,
            endedAt: nil,
            templateSnapshot: nil,
            title: nil,
            utteranceCount: utteranceCount,
            hasNotes: false,
            meetingApp: nil,
            engine: nil
        )
    }

    private func loadLegacySession(sessionID: String) -> SessionDetail? {
        let summary = loadLegacySummary(sessionID: sessionID)
        guard let summary else { return nil }

        let liveTranscript = loadJSONL(from: legacyLiveTranscriptURL(for: sessionID))

        let legacyBatchURL = legacyBatchDirectory(for: sessionID).appendingPathComponent("batch.jsonl")
        let finalTranscript = FileManager.default.fileExists(atPath: legacyBatchURL.path)
            ? loadJSONL(from: legacyBatchURL)
            : nil

        let notes: EnhancedNotes?
        if let data = try? Data(contentsOf: legacySidecarURL(for: sessionID)),
           let sidecar = try? decoder.decode(SessionSidecar.self, from: data) {
            notes = sidecar.notes
        } else {
            notes = nil
        }

        return SessionDetail(
            summary: summary,
            liveTranscript: liveTranscript,
            finalTranscript: finalTranscript?.isEmpty == false ? finalTranscript : nil,
            notes: notes
        )
    }

    private func ensureCanonicalSessionImported(sessionID: String) {
        let fm = FileManager.default
        let canonicalDirectory = canonicalSessionDirectory(for: sessionID)
        guard !fm.fileExists(atPath: canonicalDirectory.path) else { return }
        guard let legacyDetail = loadLegacySession(sessionID: sessionID) else { return }

        try? fm.createDirectory(at: sessionAudioDirectory(for: sessionID), withIntermediateDirectories: true)
        writeJSONL(legacyDetail.liveTranscript, to: liveTranscriptURL(for: sessionID))
        if let finalTranscript = legacyDetail.finalTranscript {
            writeJSONL(finalTranscript, to: finalTranscriptURL(for: sessionID))
        }
        if let notes = legacyDetail.notes {
            try? notes.markdown.write(
                to: notesMarkdownURL(for: sessionID),
                atomically: true,
                encoding: .utf8
            )
        }

        let metadata = StoredSessionMetadata(
            summary: SessionSummary(
                id: legacyDetail.summary.id,
                startedAt: legacyDetail.summary.startedAt,
                endedAt: legacyDetail.summary.endedAt,
                templateSnapshot: legacyDetail.summary.templateSnapshot,
                title: legacyDetail.summary.title,
                utteranceCount: legacyDetail.summary.utteranceCount,
                hasNotes: legacyDetail.notes != nil,
                meetingApp: legacyDetail.summary.meetingApp,
                engine: legacyDetail.summary.engine
            ),
            notesTemplate: legacyDetail.notes?.template,
            notesGeneratedAt: legacyDetail.notes?.generatedAt
        )
        writeSessionMetadata(metadata, to: canonicalDirectory)

        let legacyBatchDirectory = legacyBatchDirectory(for: sessionID)
        let sourceAudioDirectory = sessionAudioDirectory(for: sessionID)
        let audioTargets = [
            ("mic.caf", "mic.caf"),
            ("sys.caf", "sys.caf"),
            ("batch-meta.json", "batch-meta.json"),
        ]
        for (sourceName, destinationName) in audioTargets {
            let source = legacyBatchDirectory.appendingPathComponent(sourceName)
            let destination = sourceAudioDirectory.appendingPathComponent(destinationName)
            if fm.fileExists(atPath: source.path) {
                try? fm.removeItem(at: destination)
                try? fm.moveItem(at: source, to: destination)
            }
        }

        try? fm.removeItem(at: legacyLiveTranscriptURL(for: sessionID))
        try? fm.removeItem(at: legacySidecarURL(for: sessionID))
        try? fm.removeItem(at: legacyBatchDirectory.appendingPathComponent("batch.jsonl"))
        if fm.fileExists(atPath: legacyBatchDirectory.path),
           (try? fm.contentsOfDirectory(atPath: legacyBatchDirectory.path).isEmpty) == true {
            try? fm.removeItem(at: legacyBatchDirectory)
        }
    }

    private func rewriteJSONLWithRefinedText(file: URL, utterances: [Utterance]) {
        let records = loadJSONL(from: file)
        guard !records.isEmpty else { return }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var refinedLookup: [String: String] = [:]

        for utterance in utterances {
            guard let refined = utterance.refinedText else { continue }
            let key = "\(iso8601Formatter.string(from: utterance.timestamp))|\(utterance.speaker.storageKey)"
            refinedLookup[key] = refined
        }

        guard !refinedLookup.isEmpty else { return }

        let updated = records.map { record in
            guard record.refinedText == nil else { return record }
            let key = "\(iso8601Formatter.string(from: record.timestamp))|\(record.speaker.storageKey)"
            if let refined = refinedLookup[key] {
                return record.withRefinedText(refined)
            }
            return record
        }

        writeJSONL(updated, to: file)
    }

    private func makeSessionID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "session_\(formatter.string(from: date))"
    }
}
