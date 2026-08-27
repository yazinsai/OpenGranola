import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Format

enum ExportFormat: CaseIterable {
    case plainText
    case pdf
    case docx

    var menuTitle: String {
        switch self {
        case .plainText: "Plain Text (.txt)"
        case .pdf: "PDF (.pdf)"
        case .docx: "Word (.docx)"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .pdf: "pdf"
        case .docx: "docx"
        }
    }

    var contentType: UTType {
        switch self {
        case .plainText: .plainText
        case .pdf: .pdf
        case .docx: UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        }
    }
}

// MARK: - Content Exporter

/// Saves meeting content to a user-chosen file as plain text, PDF, or Word.
@MainActor
enum ContentExporter {
    enum ExportError: LocalizedError {
        case pdfGenerationFailed

        var errorDescription: String? {
            switch self {
            case .pdfGenerationFailed: "The PDF could not be generated."
            }
        }
    }

    static func export(
        plainText: @autoclosure () -> String,
        attributedText: @autoclosure () -> NSAttributedString,
        format: ExportFormat,
        suggestedFileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(sanitizedFileName(suggestedFileName)).\(format.fileExtension)"
        // The main window is a non-activating panel; without this the save
        // dialog can open behind other windows.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch format {
            case .plainText:
                try plainText().write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                try writePDF(resolvingColors(in: attributedText()), to: url)
            case .docx:
                try writeDocx(resolvingColors(in: attributedText()), to: url)
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Export" : cleaned
    }

    // MARK: Writers

    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let printInfo = NSPrintInfo()
        printInfo.topMargin = 54
        printInfo.bottomMargin = 54
        printInfo.leftMargin = 54
        printInfo.rightMargin = 54
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.appearance = NSAppearance(named: .aqua)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.size = NSSize(width: pageWidth, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(text)

        var contentHeight: CGFloat = 1
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            contentHeight = max(ceil(layoutManager.usedRect(for: container).height), 1)
        }
        textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: contentHeight)

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw ExportError.pdfGenerationFailed
        }
    }

    private static func writeDocx(_ text: NSAttributedString, to url: URL) throws {
        let data = try text.data(
            from: NSRange(location: 0, length: text.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
        )
        try data.write(to: url, options: .atomic)
    }

    /// Resolves dynamic system colors to light appearance so a dark-mode
    /// export doesn't come out as white text on a white page.
    private static func resolvingColors(in text: NSAttributedString) -> NSAttributedString {
        guard let aqua = NSAppearance(named: .aqua) else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        result.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: result.length)
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            var resolved = color
            aqua.performAsCurrentDrawingAppearance {
                resolved = NSColor(cgColor: color.cgColor) ?? color
            }
            result.addAttribute(.foregroundColor, value: resolved, range: range)
        }
        return result
    }
}
