import SwiftUI
import WidgetKit

@main
struct VarioRadarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RadarLiveActivity()
        RadarStatusWidget()
    }
}
