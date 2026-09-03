import SwiftUI
import WidgetKit

struct EnzoTodayWidget: Widget {
    static let kind = "com.btn0s.enzo.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            EnzoTodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [ActivityPalette.heroStart, ActivityPalette.heroEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Enzo")
        .description("Next feed countdown and today’s totals.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .pushHandler(EnzoWidgetPushHandler.self)
    }
}

private struct EnzoWidgetPushHandler: WidgetPushHandler {
    init() {}

    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let enabled = widgets.contains { $0.kind == EnzoTodayWidget.kind }
        Task {
            try? await WidgetRemoteClient().registerPushToken(pushInfo.token, enabled: enabled)
        }
    }
}

private struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let cached = WidgetSnapshotStore.load()
        Task {
            let snapshot = await WidgetSnapshotRefresher {
                try await WidgetRemoteClient().state()
            }.refresh(cached: cached)
            if let snapshot {
                try? AlarmRuntimeStore.cancelIfStale(remoteDueAt: snapshot.nextFeedAt)
                WidgetSnapshotStore.save(snapshot)
            }

            let now = Date()
            // The countdown text ticks on its own; re-render when the feed comes
            // due so "Due now" appears, otherwise at the next local midnight.
            var refresh = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            if let next = snapshot?.nextFeedAt, next > now, next < refresh {
                refresh = next
            }
            completion(Timeline(
                entries: [SnapshotEntry(date: now, snapshot: snapshot)],
                policy: .after(refresh)
            ))
        }
    }
}

private struct EnzoTodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessory
        case .systemMedium:
            HStack(spacing: 14) {
                nextFeed
                Divider().overlay(ActivityPalette.muted.opacity(0.35))
                totals
            }
        default:
            nextFeed
        }
    }

    private var nextFeed: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT FEED")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(ActivityPalette.accentEyebrow)

            countdown
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(ActivityPalette.ink)

            dueLabel
                .font(.caption.weight(.medium))
                .foregroundStyle(ActivityPalette.muted)
                .lineLimit(2)

            Spacer(minLength: 0)

            if let snapshot {
                Text("Day \(snapshot.dayOfLife)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ActivityPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY")
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(ActivityPalette.accentEyebrow)

            if let snapshot {
                total("Milk", snapshot.volumeUnit.format(ml: snapshot.milkMl))
                total("Feeds", "\(snapshot.feeds)")
                total("Pee", "\(snapshot.pees)")
                total("Poop", "\(snapshot.poops)")
            } else {
                Text("Open Enzo to sync")
                    .font(.caption)
                    .foregroundStyle(ActivityPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func total(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ActivityPalette.muted)
            Spacer(minLength: 6)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(ActivityPalette.ink)
        }
    }

    private var accessory: some View {
        HStack(spacing: 8) {
            Image("BabyBottle")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 12, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Next feed")
                    .font(.caption2.weight(.semibold))
                countdown
                    .font(.headline.monospacedDigit())
                if let snapshot {
                    Text("\(snapshot.feeds) feeds · \(snapshot.volumeUnit.format(ml: snapshot.milkMl))")
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if let next = snapshot?.nextFeedAt {
            if next > Date.now {
                Text(timerInterval: Date.now...next, countsDown: true)
            } else {
                Text("Due now")
            }
        } else {
            Text("—")
        }
    }

    @ViewBuilder
    private var dueLabel: some View {
        if let next = snapshot?.nextFeedAt {
            Text("Due at \(next.formatted(date: .omitted, time: .shortened))")
        } else if snapshot == nil {
            Text("Open Enzo to sync")
        } else {
            Text("Log a feed to start the clock")
        }
    }
}
