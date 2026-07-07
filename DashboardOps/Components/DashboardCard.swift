//
//  DashboardCard.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Dark rounded card surface used across the app shell.
struct DashboardCard<Content: View>: View {
    private let content: Content

    /// Creates a card with custom content.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DashboardTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius, style: .continuous))
    }
}
