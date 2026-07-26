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
                Label("Check-in here", systemImage: "location.fill")
                    .controlWidgetActionHint("Start a check-in")
            }
            .tint(
                Color(
                    red: 212.0 / 255.0,
                    green: 111.0 / 255.0,
                    blue: 77.0 / 255.0
                )
            )
        }
        .displayName("Check-in here")
        .description("Open rec.me to check in at the place where you are.")
    }
}
