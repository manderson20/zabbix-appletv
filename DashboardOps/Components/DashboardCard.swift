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
    private let backgroundColor: Color?

    /// Creates a card with custom content, optionally overriding the default dark surface with
    /// a widget-specific background color (e.g. Zabbix's own per-item "bg_color" field).
    init(backgroundColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(backgroundColor ?? DashboardTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius, style: .continuous))
    }
}
