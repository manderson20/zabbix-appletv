//
//  DashboardWidgetGridView.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Lays out resolved dashboard widgets in their relative grid positions.
///
/// The number of grid columns/rows is derived from the widgets themselves (the furthest extent
/// any widget reaches) rather than a hardcoded constant, since Zabbix's dashboard grid size has
/// varied across versions.
struct DashboardWidgetGridView: View {
    /// Widgets to lay out.
    let widgets: [RenderableDashboardWidget]

    /// Computes the grid's column and row count as the furthest extent any widget reaches.
    static func gridExtent(for widgets: [RenderableDashboardWidget]) -> (columns: Int, rows: Int) {
        let columns = max(widgets.map { $0.frame.x + $0.frame.width }.max() ?? 1, 1)
        let rows = max(widgets.map { $0.frame.y + $0.frame.height }.max() ?? 1, 1)
        return (columns, rows)
    }

    var body: some View {
        let (columnCount, rowCount) = Self.gridExtent(for: widgets)

        GeometryReader { geometry in
            let columnWidth = geometry.size.width / CGFloat(columnCount)
            let rowHeight = geometry.size.height / CGFloat(rowCount)

            ZStack(alignment: .topLeading) {
                ForEach(widgets) { widget in
                    DashboardWidgetCardView(widget: widget)
                        .frame(
                            width: columnWidth * CGFloat(widget.frame.width),
                            height: rowHeight * CGFloat(widget.frame.height)
                        )
                        .offset(
                            x: columnWidth * CGFloat(widget.frame.x),
                            y: rowHeight * CGFloat(widget.frame.y)
                        )
                }
            }
        }
    }
}

/// A single dashboard widget rendered natively.
private struct DashboardWidgetCardView: View {
    let widget: RenderableDashboardWidget

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(widget.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)

                content
            }
        }
        .padding(6)
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case .clock:
            ClockWidgetContentView()
        case let .itemValue(name, value, units):
            ItemValueWidgetContentView(name: name, value: value, units: units)
        case let .problems(problems):
            ProblemsWidgetContentView(problems: problems)
        case let .unsupported(rawType):
            Text("The \"\(rawType)\" widget isn't supported yet.")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        }
    }
}

private struct ClockWidgetContentView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, style: .time)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
        }
    }
}

private struct ItemValueWidgetContentView: View {
    let name: String
    let value: String
    let units: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(units.isEmpty ? value : "\(value) \(units)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(name)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

private struct ProblemsWidgetContentView: View {
    let problems: [DashboardProblem]

    var body: some View {
        if problems.isEmpty {
            Text("No active problems")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(problems.prefix(6)) { problem in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(problem.severityColor)
                            .frame(width: 14, height: 14)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.name)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)

                            if let host = problem.host {
                                Text(host)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension DashboardProblem {
    var severityColor: Color {
        switch severity {
        case 0: .gray
        case 1: .teal
        case 2: .yellow
        case 3: .orange
        case 4: Color(red: 0.95, green: 0.35, blue: 0.2)
        default: .red
        }
    }
}
