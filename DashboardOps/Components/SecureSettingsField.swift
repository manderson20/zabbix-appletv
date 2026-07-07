//
//  SecureSettingsField.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Labeled secure text field used by configuration screens.
struct SecureSettingsField: View {
    /// Field label.
    let title: String

    /// Text value binding.
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)

            SecureField(title, text: $text)
                .font(.system(size: 28, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(DashboardTheme.secondaryCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius, style: .continuous))
        }
    }
}
