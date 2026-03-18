import SwiftUI

struct TranscriptView: View {
    let utterances: [Utterance]
    let volatileYouText: String
    let volatileThemText: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(utterances) { utterance in
                        UtteranceBubble(utterance: utterance)
                            .id(utterance.id)
                    }

                    // Volatile text
                    if !volatileYouText.isEmpty {
                        VolatileIndicator(text: volatileYouText, speaker: .you)
                            .id("volatile-you")
                    }

                    if !volatileThemText.isEmpty {
                        VolatileIndicator(text: volatileThemText, speaker: .them)
                            .id("volatile-them")
                    }
                }
                .padding(16)
            }
            .onChange(of: utterances.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = utterances.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: volatileYouText) {
                proxy.scrollTo("volatile-you", anchor: .bottom)
            }
            .onChange(of: volatileThemText) {
                proxy.scrollTo("volatile-them", anchor: .bottom)
            }
        }
    }
}

private struct UtteranceBubble: View {
    let utterance: Utterance

    private var textIsRTL: Bool { utterance.text.isRTL }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(utterance.speaker == .you ? "You" : "Them")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(utterance.speaker == .you ? Color.youColor : Color.themColor)
                .frame(width: 36, alignment: .trailing)

            Text(utterance.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .multilineTextAlignment(textIsRTL ? .trailing : .leading)
                .environment(\.layoutDirection, textIsRTL ? .rightToLeft : .leftToRight)
                .frame(maxWidth: .infinity, alignment: textIsRTL ? .trailing : .leading)
        }
    }
}

private struct VolatileIndicator: View {
    let text: String
    let speaker: Speaker

    private var textIsRTL: Bool { text.isRTL }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(speaker == .you ? "You" : "Them")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(speaker == .you ? Color.youColor : Color.themColor)
                .frame(width: 36, alignment: .trailing)

            HStack(spacing: 4) {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(textIsRTL ? .trailing : .leading)
                    .environment(\.layoutDirection, textIsRTL ? .rightToLeft : .leftToRight)
                Circle()
                    .fill(speaker == .you ? Color.youColor : Color.themColor)
                    .frame(width: 4, height: 4)
                    .opacity(0.6)
            }
            .frame(maxWidth: .infinity, alignment: textIsRTL ? .trailing : .leading)
        }
        .opacity(0.6)
    }
}

// MARK: - RTL Detection

extension String {
    /// Returns true if the majority of the string's alphabetic characters are in RTL scripts (Hebrew, Arabic, etc.).
    var isRTL: Bool {
        var rtlCount = 0
        var ltrCount = 0
        for scalar in unicodeScalars {
            let value = scalar.value
            let isRTLChar = (0x0590...0x05FF).contains(value) ||
                            (0xFB1D...0xFB4F).contains(value) ||
                            (0x0600...0x06FF).contains(value) ||
                            (0x0750...0x077F).contains(value) ||
                            (0x08A0...0x08FF).contains(value) ||
                            (0xFB50...0xFDFF).contains(value) ||
                            (0xFE70...0xFEFF).contains(value)
            if isRTLChar {
                rtlCount += 1
            } else if scalar.properties.isAlphabetic {
                ltrCount += 1
            }
        }
        return rtlCount > ltrCount && rtlCount > 0
    }
}

// MARK: - Colors

extension Color {
    static let youColor = Color(red: 0.35, green: 0.55, blue: 0.75)    // muted blue
    static let themColor = Color(red: 0.82, green: 0.6, blue: 0.3)     // warm amber
    static let accentTeal = Color(red: 0.15, green: 0.55, blue: 0.55)  // deep teal
}
