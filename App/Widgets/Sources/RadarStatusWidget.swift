import SwiftUI
import VarioRadarCore
import WidgetKit

/// A timeline-driven Home Screen / Lock Screen / StandBy widget showing the
/// last known radar status from the App Group snapshot. This is NOT live
/// data (WidgetKit's refresh budget is far too small); it is an at-a-glance
/// "what did the radar last see" tile. The live surface is the Live
/// Activity.
struct RadarStatusWidget: Widget {
    let kind = "RadarStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RadarStatusProvider()) { entry in
            RadarStatusEntryView(entry: entry)
                .containerBackground(.black.gradient, for: .widget)
        }
        .configurationDisplayName("Radar status")
        .description("The last vehicle your Varia radar reported.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct RadarStatusEntry: TimelineEntry {
    let date: Date
    let presentation: RadarPresentation
}

struct RadarStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadarStatusEntry {
        RadarStatusEntry(date: Date(), presentation: .clear)
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarStatusEntry) -> Void) {
        completion(RadarStatusEntry(date: Date(), presentation: AppGroup.readSnapshot() ?? .clear))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarStatusEntry>) -> Void) {
        let entry = RadarStatusEntry(date: Date(), presentation: AppGroup.readSnapshot() ?? .clear)
        // Refresh roughly every 15 minutes; this widget is not a live feed.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RadarStatusEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: RadarStatusEntry

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                icon.font(.system(size: 40))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.presentation.isClear ? "Road clear" : "Vehicle behind")
                        .font(.headline)
                        .foregroundStyle(.white)
                    if !entry.presentation.isClear {
                        Text(detailText)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        default:
            VStack(spacing: 6) {
                icon.font(.title2)
                Text(entry.presentation.isClear ? "Clear" : entry.presentation.compactText)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }

    private var icon: some View {
        Image(systemName: entry.presentation.highestLevel.symbolName)
            .foregroundStyle(entry.presentation.highestLevel.color)
    }

    private var detailText: String {
        let distance = entry.presentation.nearestDistanceMeters.map { "\($0) m" } ?? ""
        let speed = entry.presentation.nearestSpeedKmh.map { "\($0) km/h" } ?? ""
        return [distance, speed].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
