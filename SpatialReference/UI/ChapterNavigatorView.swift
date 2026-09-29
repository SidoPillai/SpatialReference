//
//  ChapterNavigatorView.swift
//  SpatialReference
//

import SwiftUI

/// A horizontal row of chapter chips using visionOS's glass button styles.
struct ChapterNavigatorView: View {
    let chapters: [Chapter]
    @Binding var currentIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, _ in
                    Button {
                        currentIndex = index
                    } label: {
                        Text("\(index + 1)")
                            .frame(width: 36, height: 36)
                    }
                    .tint(index == currentIndex ? .blue : nil)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    @Previewable @State var index = 0
    ChapterNavigatorView(
        chapters: (0..<5).map { Chapter(id: "c\($0)", narrationText: "Chapter \($0)", media: nil) },
        currentIndex: $index
    )
    .padding()
}
