import WidgetKit
import SwiftUI

@main
struct SignInActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            SignInActivityWidget()
        }
    }
}
