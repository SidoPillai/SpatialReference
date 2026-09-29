//
//  HighlightedCaptionView.swift
//  SpatialReference
//

import SwiftUI

/// Renders narration text with the word currently being spoken highlighted.
/// Words already spoken are bright, upcoming words are dimmed. When nothing is
/// being narrated, the whole text is shown at full brightness.
struct HighlightedCaptionView: View {
    let text: String
    let highlightedRange: NSRange?
    var isNarrating: Bool = true
    var highlightColor = Color(red: 0.949, green: 0.784, blue: 0.475)

    var body: some View {
        Text(attributedString)
            .font(.system(size: 27, design: .serif))
            .lineSpacing(14)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = .white

        guard isNarrating, let highlightedRange,
              let stringRange = Range(highlightedRange, in: text),
              let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else {
            return attributed
        }

        attributed[upper..<attributed.endIndex].foregroundColor = .white.opacity(0.62)
        attributed[lower..<upper].foregroundColor = Color(red: 0.118, green: 0.102, blue: 0.086)
        attributed[lower..<upper].backgroundColor = highlightColor
        return attributed
    }
}

#Preview {
    HighlightedCaptionView(
        text: "The quick brown fox jumps over the lazy dog.",
        highlightedRange: NSRange(location: 4, length: 5)
    )
    .padding()
    .background(.black)
}
