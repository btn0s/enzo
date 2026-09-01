import ActivityKit
import SwiftUI
import WidgetKit

struct FeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeedActivityAttributes.self) { context in
            HStack(spacing: 14) {
                feedGlyph(width: 17, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    primaryStatus(for: context.state)
                        .font(.headline.weight(.semibold))
                    secondaryTimer(for: context.state)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.phase == .feeding ? "Finish" : "Start")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.18), in: .capsule)
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.91, green: 0.78, blue: 0.67))
            .activitySystemActionForegroundColor(Color(red: 0.20, green: 0.16, blue: 0.13))
            .widgetURL(URL(string: "enzo://feed/start"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    feedGlyph(width: 14, height: 20)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        primaryStatus(for: context.state)
                            .font(.headline.weight(.semibold))
                        secondaryTimer(for: context.state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase == .feeding ? "Finish" : "Start").font(.caption.bold())
                }
            } compactLeading: {
                feedGlyph(width: 10, height: 16)
            } compactTrailing: {
                compactStatus(for: context.state)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 48)
            } minimal: {
                feedGlyph(width: 10, height: 16)
            }
            .widgetURL(URL(string: "enzo://feed/start"))
        }
    }

    private func feedGlyph(width: CGFloat, height: CGFloat) -> some View {
        Image("BabyBottle")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func compactStatus(for state: FeedActivityAttributes.ContentState) -> some View {
        if state.phase == .waiting, let next = state.nextFeedAt {
            Text(next, style: .time)
        } else {
            secondaryTimer(for: state)
        }
    }

    @ViewBuilder
    private func primaryStatus(for state: FeedActivityAttributes.ContentState) -> some View {
        if state.phase == .feeding {
            Text("Feeding Enzo")
        } else if let next = state.nextFeedAt {
            Text("Next feed \(next.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("Next feed —")
        }
    }

    @ViewBuilder
    private func secondaryTimer(for state: FeedActivityAttributes.ContentState) -> some View {
        if state.phase == .feeding, let start = state.startedAt {
            Text(start, style: .timer).monospacedDigit()
        } else if let next = state.nextFeedAt {
            Text(timerInterval: Date.now...max(next, Date.now), countsDown: true).monospacedDigit()
        } else {
            Text("Ready")
        }
    }
}
