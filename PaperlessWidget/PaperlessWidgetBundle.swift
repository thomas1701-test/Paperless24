//
//  PaperlessWidgetBundle.swift
//  PaperlessWidget
//
//  Created by Thomas on 15.05.26.
//

import WidgetKit
import SwiftUI

@main
struct PaperlessWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaperlessWidget()
        PaperlessWidgetControl()
        PaperlessWidgetLiveActivity()
    }
}
