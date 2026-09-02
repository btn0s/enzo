import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct FeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FeedActivityAttributes.self) { context in
            lockScreenBanner(for: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    glyphBadge(diameter: 40, width: 14, height: 20)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        eyebrow
                        countdown(for: context.state)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    dueLabel(for: context.state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
            } compactLeading: {
                feedGlyph(width: 10, height: 16)
                    .foregroundStyle(ActivityPalette.islandAccent)
            } compactTrailing: {
                countdown(for: context.state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ActivityPalette.islandAccent)
                    .frame(maxWidth: 44)
            } minimal: {
                feedGlyph(width: 10, height: 16)
                    .foregroundStyle(ActivityPalette.islandAccent)
            }
            .keylineTint(ActivityPalette.islandAccent)
        }
    }

    private func lockScreenBanner(for state: FeedActivityAttributes.ContentState) -> some View {
        HStack(spacing: 14) {
            glyphBadge(diameter: 46, width: 16, height: 23)

            VStack(alignment: .leading, spacing: 3) {
                eyebrow
                countdown(for: state)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(ActivityPalette.ink)
                dueLabel(for: state)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ActivityPalette.muted)
            }

            Spacer(minLength: 10)

            Text("Open")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ActivityPalette.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(ActivityPalette.accent, in: .capsule)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .activityBackgroundTint(ActivityPalette.heroStart)
        .activitySystemActionForegroundColor(ActivityPalette.ink)
    }

    private var eyebrow: some View {
        Text("NEXT FEED")
            .font(.caption2.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(ActivityPalette.accentEyebrow)
    }

    private func glyphBadge(diameter: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        feedGlyph(width: width, height: height)
            .foregroundStyle(ActivityPalette.accent)
            .frame(width: diameter, height: diameter)
            .background(ActivityPalette.accentSoft, in: .circle)
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
    private func countdown(for state: FeedActivityAttributes.ContentState) -> some View {
        if let next = state.nextFeedAt {
            if next > Date.now {
                Text(timerInterval: Date.now...next, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
            } else {
                Text("Due now")
            }
        } else {
            Text("—")
        }
    }

    @ViewBuilder
    private func dueLabel(for state: FeedActivityAttributes.ContentState) -> some View {
        if let next = state.nextFeedAt {
            Text("Due at \(next.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("Log a feed to start the clock")
        }
    }
}

/// Mirrors `EnzoPalette` in the app target; the widget extension cannot see it.
enum ActivityPalette {
    static let heroStart = dynamic(light: 0xF3D5C5, dark: 0x3B2921)
    static let heroEnd = dynamic(light: 0xF8EEE3, dark: 0x29231F)
    static let ink = dynamic(light: 0x221B17, dark: 0xF8F1E8)
    static let muted = dynamic(light: 0x665C55, dark: 0xBFB4A9)
    static let accent = dynamic(light: 0x7B3F2E, dark: 0xE4A184)
    static let onAccent = dynamic(light: 0xFFF9F3, dark: 0x211713)
    static let accentSoft = dynamic(light: 0xFFF9F3, dark: 0x211713).opacity(0.55)
    static let accentEyebrow = dynamic(light: 0x7B3F2E, dark: 0xE4A184)
    /// The Dynamic Island is always rendered on black; use the dark-mode accent.
    static let islandAccent = Color(red: 0xE4 / 255, green: 0xA1 / 255, blue: 0x84 / 255)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(
                red: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) >> 16 & 0xFF) / 255,
                green: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) >> 8 & 0xFF) / 255,
                blue: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
