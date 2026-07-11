//
//  ScreenScaffold.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Full-screen tvOS layout container.
struct ScreenScaffold<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    /// Creates a screen scaffold.
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            DashboardTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 28, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }

                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DashboardTheme.horizontalScreenPadding)
            .padding(.vertical, DashboardTheme.verticalScreenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
