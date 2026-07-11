//
//  AutoScrollingContent.swift
//  DashboardOps
//
//  Created by Codex on 7/10/26.
//

import SwiftUI

/// Wraps list-style widget content in a container that scrolls itself when the content is taller
/// than the space available — an unattended kiosk display has no remote to scroll manually, so a
/// plain `ScrollView` just permanently hides whatever doesn't fit in the first screenful. Content
/// that already fits behaves exactly like a static view; nothing moves.
struct AutoScrollingContent<Content: View>: View {
    @ViewBuilder let content: Content

    /// Pause before scrolling starts, so the first rows are readable immediately rather than
    /// already sliding away.
    private static var pauseNanoseconds: UInt64 { 3 * 1_000_000_000 }

    /// How fast overflowing content scrolls, in points per second — matches the same pacing used
    /// for overflowing dashboard pages, so the whole app scrolls at one consistent speed.
    private static var pointsPerSecond: CGFloat { 40 }

    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { outerGeometry in
            let overflow = (contentHeight - outerGeometry.size.height).rounded()

            content
                .background(
                    GeometryReader { innerGeometry in
                        Color.clear.onAppear { contentHeight = innerGeometry.size.height }
                            .onChange(of: innerGeometry.size.height) { _, newHeight in
                                contentHeight = newHeight
                            }
                    }
                )
                .frame(width: outerGeometry.size.width, alignment: .top)
                .offset(y: -scrollOffset)
                .frame(width: outerGeometry.size.width, height: outerGeometry.size.height, alignment: .top)
                .clipped()
                .task(id: overflow) {
                    guard overflow > 0 else { return }

                    try? await Task.sleep(nanoseconds: Self.pauseNanoseconds)
                    guard !Task.isCancelled else { return }

                    withAnimation(.linear(duration: Double(overflow / Self.pointsPerSecond))) {
                        scrollOffset = overflow
                    }
                }
        }
    }
}
