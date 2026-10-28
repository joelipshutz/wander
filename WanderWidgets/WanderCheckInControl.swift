import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct WanderCheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: WanderWidgetConstants.checkInControlKind
        ) {
            ControlWidgetButton(
                action: WanderOpenCheckInControlIntent(target: .checkInHere)
            ) {
                Label("Check-In", systemImage: "plus")
                    .controlWidgetActionHint("Start A Check-In")
            }
            .tint(
                Color(
                    red: 212.0 / 255.0,
                    green: 111.0 / 255.0,
                    blue: 77.0 / 255.0
                )
            )
        }
        .displayName("Check-In")
        .description("Open Astir To Check In At The Place Where You Are.")
    }
}
