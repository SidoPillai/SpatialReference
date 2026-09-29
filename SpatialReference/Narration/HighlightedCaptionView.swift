//
//  HighlightedCaptionView.swift
//  SpatialReference
//

import SwiftUI

/// Renders narration text with the word currently being spoken highlighted,
/// dimming the rest.
struct HighlightedCaptionView: View {
    let text: String
    let highlightedRange: NSRange?

    var body: some View {
        Text(attributedString)
            .font(.title3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = .secondary

        guard let highlightedRange,
              let stringRange = Range(highlightedRange, in: text),
              let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else {
            return attributed
        }

        attributed[lower..<upper].foregroundColor = .primary
        attributed[lower..<upper].backgroundColor = .yellow.opacity(0.35)
        return attributed
    }
}

#Preview {
    HighlightedCaptionView(
        text: "The quick brown fox jumps over the lazy dog.",
        highlightedRange: NSRange(location: 4, length: 5)
    )
    .padding()
}
