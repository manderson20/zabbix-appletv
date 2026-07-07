//
//  ProviderStatusBadge.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Small status badge for provider support.
struct ProviderStatusBadge: View {
    /// Provider support status.
    let status: ProviderSupportStatus

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .supported:
            "Supported"
        case .planned:
            "Planned"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .supported:
            .white
        case .planned:
            DashboardTheme.secondaryText
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .supported:
            DashboardTheme.accent
        case .planned:
            DashboardTheme.secondaryCardBackground
        }
    }
}
