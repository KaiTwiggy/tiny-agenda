import AppKit
import TinyAgendaCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isRefreshing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Updating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            if let err = viewModel.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                if let cached = viewModel.lastSuccessfulRefresh {
                    Text(staleDataCaption(updated: cached))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
            }

            let upcoming = viewModel.upcomingVisibleEvents()
                .prefix(12)

            if upcoming.isEmpty {
                Text(viewModel.feedURLString.isEmpty ? "Add a calendar URL in Settings." : "No upcoming events.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(Array(upcoming)) { ev in
                    EventRow(event: ev) {
                        viewModel.hideEvent(id: ev.id)
                    }
                }
            }

            Divider()

            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openTinyAgendaSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            if let url = viewModel.upcomingVisibleEvents().first(where: { $0.joinURL != nil })?.joinURL {
                Button("Join next meeting") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Refresh") {
                Task { await viewModel.refresh() }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .frame(width: 320)
    }

    private func staleDataCaption(updated: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "List below is from the last successful update (\(f.string(from: updated)))."
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 108, alignment: .leading)
                Text(event.shortTitle)
                    .font(.body)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Hide") {
                    onHide()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Hide this occurrence from the menu bar and reminders until it leaves the calendar feed")
            }
            if let url = event.joinURL {
                Button("Open link") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Hide this event") {
                onHide()
            }
        }
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        if event.isAllDay {
            return "All day"
        }
        return "\(f.string(from: event.start)) – \(f.string(from: event.end))"
    }
}
