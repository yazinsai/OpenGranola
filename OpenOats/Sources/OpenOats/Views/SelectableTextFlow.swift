import AppKit
import SwiftUI

// MARK: - Selectable Text Flow

/// Renders an attributed string in a single non-editable `NSTextView`, so a
/// selection can span the whole content (drag across lines, Cmd+A, Cmd+C).
/// SwiftUI's per-`Text` `.textSelection(.enabled)` cannot select across views,
/// which limited transcript and notes selection to one paragraph at a time.
struct SelectableTextFlow: NSViewRepresentable {
    let attributedText: NSAttributedString
    /// Called when a link in the text is clicked, with the link URL and the
    /// bounding rect of the link run in the view's coordinate space. Return
    /// true if handled; returning false falls back to the system behavior.
    /// When nil, all links use the system behavior (open URL).
    var onLinkClick: ((URL, CGRect) -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        // Links carry their own styling in the attributed string; just show a hand cursor.
        view.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.onLinkClick = onLinkClick
        guard let storage = nsView.textStorage else { return }
        guard !storage.isEqual(to: attributedText) else { return }

        let previousSelection = nsView.selectedRanges
        storage.setAttributedString(attributedText)

        // Keep the selection alive across live-transcript updates (text appends
        // at the end, so absolute offsets stay valid).
        let length = attributedText.length
        let restored = previousSelection.compactMap { value -> NSValue? in
            let range = value.rangeValue
            guard range.location <= length else { return nil }
            return NSValue(range: NSRange(
                location: range.location,
                length: min(range.length, length - range.location)
            ))
        }
        if !restored.isEmpty {
            nsView.selectedRanges = restored
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let layoutManager = nsView.layoutManager,
              let container = nsView.textContainer else { return nil }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let height = ceil(layoutManager.usedRect(for: container).height)
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onLinkClick: ((URL, CGRect) -> Bool)?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let onLinkClick else { return false }
            let url: URL?
            if let linkURL = link as? URL {
                url = linkURL
            } else if let linkString = link as? String {
                url = URL(string: linkString)
            } else {
                url = nil
            }
            guard let url else { return false }

            var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
            if let layoutManager = textView.layoutManager,
               let container = textView.textContainer,
               let storage = textView.textStorage,
               charIndex < storage.length {
                var linkRange = NSRange(location: charIndex, length: 1)
                _ = storage.attribute(
                    .link,
                    at: charIndex,
                    longestEffectiveRange: &linkRange,
                    in: NSRange(location: 0, length: storage.length)
                )
                let glyphRange = layoutManager.glyphRange(forCharacterRange: linkRange, actualCharacterRange: nil)
                rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
                rect.origin.x += textView.textContainerOrigin.x
                rect.origin.y += textView.textContainerOrigin.y
            }
            return onLinkClick(url, rect)
        }
    }
}

// MARK: - Transcript Flow Builder

/// Builds the transcript as one attributed string whose column layout mirrors
/// the previous per-row HStack: optional right-aligned timestamp column, then a
/// right-aligned speaker column, then the utterance text with hanging indent.
enum TranscriptFlow {
    static let renameLinkScheme = "openoats-rename"

    struct Line {
        var timestamp: String?      // nil hides the timestamp for this row
        var speakerLabel: String
        var speakerColor: NSColor
        var renameKey: String?      // non-nil makes the speaker label a rename link
        var text: String
        var textIsSecondary: Bool = false
    }

    static func renameURL(forKey key: String) -> URL? {
        URL(string: "\(renameLinkScheme)://speaker/\(key)")
    }

    static func renameKey(from url: URL) -> String? {
        guard url.scheme == renameLinkScheme else { return nil }
        return url.lastPathComponent
    }

    static func speakerColumnWidth(forLabels labels: [String]) -> CGFloat {
        let font = speakerFont()
        return labels.reduce(CGFloat(36)) { widest, label in
            max(widest, ceil((label as NSString).size(withAttributes: [.font: font]).width))
        }
    }

    static func attributed(
        lines: [Line],
        showsTimestampColumn: Bool,
        timestampColumnWidth: CGFloat = 34
    ) -> NSAttributedString {
        let timestampFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let bodyFont = NSFont.systemFont(ofSize: 13)
        let speakerFont = speakerFont()

        let timestampWidth = timestampColumnWidth
        let speakerWidth = speakerColumnWidth(forLabels: lines.map(\.speakerLabel))
        let speakerRightEdge = showsTimestampColumn ? timestampWidth + 6 + speakerWidth : speakerWidth
        let textStart = speakerRightEdge + (showsTimestampColumn ? 6 : 8)

        let paragraph = NSMutableParagraphStyle()
        var tabs: [NSTextTab] = []
        if showsTimestampColumn {
            tabs.append(NSTextTab(textAlignment: .right, location: timestampWidth))
        }
        tabs.append(NSTextTab(textAlignment: .right, location: speakerRightEdge))
        tabs.append(NSTextTab(textAlignment: .left, location: textStart))
        paragraph.tabStops = tabs
        paragraph.headIndent = textStart
        paragraph.paragraphSpacing = 8
        paragraph.lineBreakMode = .byWordWrapping

        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont,
                    .paragraphStyle: paragraph,
                ]))
            }

            let timestampField = showsTimestampColumn ? "\t\(line.timestamp ?? "")\t" : "\t"
            result.append(NSAttributedString(string: timestampField, attributes: [
                .font: timestampFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraph,
            ]))

            var speakerAttributes: [NSAttributedString.Key: Any] = [
                .font: speakerFont,
                .foregroundColor: line.speakerColor,
                .paragraphStyle: paragraph,
            ]
            if let key = line.renameKey, let url = renameURL(forKey: key) {
                speakerAttributes[.link] = url
                speakerAttributes[.toolTip] = "Rename speaker"
            }
            result.append(NSAttributedString(string: line.speakerLabel, attributes: speakerAttributes))

            result.append(NSAttributedString(string: "\t\(line.text)", attributes: [
                .font: bodyFont,
                .foregroundColor: line.textIsSecondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    private static func speakerFont() -> NSFont {
        NSFont.systemFont(ofSize: 11, weight: .semibold)
    }
}

// MARK: - Markdown Flow Builder

/// Converts note markdown pieces into attributed strings for a single
/// selectable flow, matching the previous per-block `Text` styling.
enum MarkdownTextFlow {
    /// Blank-line separator between blocks: a newline ends the previous
    /// paragraph, then an empty paragraph with a fixed line height provides the
    /// vertical gap (copies out as a plain blank line).
    static func blockSeparator(gap: CGFloat = 12) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13),
        ])
        let gapStyle = NSMutableParagraphStyle()
        gapStyle.minimumLineHeight = gap
        gapStyle.maximumLineHeight = gap
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 2),
            .paragraphStyle: gapStyle,
        ]))
        return result
    }

    static func heading(_ text: String, level: Int) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = level == 1 ? 4 : 2
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: level == 1 ? 18 : 15, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ])
    }

    static func inlineMarkdown(_ text: String) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 13)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping

        let parsed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var font = baseFont
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                }
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if !traits.isEmpty {
                    let descriptor = font.fontDescriptor.withSymbolicTraits(
                        font.fontDescriptor.symbolicTraits.union(traits)
                    )
                    font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributes[.font] = font
            result.append(NSAttributedString(string: String(parsed.characters[run.range]), attributes: attributes))
        }
        return result
    }
}
