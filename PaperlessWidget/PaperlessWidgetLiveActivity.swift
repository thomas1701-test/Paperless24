//
//  PaperlessWidgetLiveActivity.swift
//  PaperlessWidget
//
//  Created by Thomas on 15.05.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PaperlessWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct PaperlessWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaperlessWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension PaperlessWidgetAttributes {
    fileprivate static var preview: PaperlessWidgetAttributes {
        PaperlessWidgetAttributes(name: "World")
    }
}

extension PaperlessWidgetAttributes.ContentState {
    fileprivate static var smiley: PaperlessWidgetAttributes.ContentState {
        PaperlessWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: PaperlessWidgetAttributes.ContentState {
         PaperlessWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: PaperlessWidgetAttributes.preview) {
   PaperlessWidgetLiveActivity()
} contentStates: {
    PaperlessWidgetAttributes.ContentState.smiley
    PaperlessWidgetAttributes.ContentState.starEyes
}
