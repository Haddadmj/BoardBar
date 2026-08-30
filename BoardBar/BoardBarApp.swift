import BoardBarCore
import SwiftUI

@main
struct BoardBarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // `.window` style gives a real popover that can host an arbitrary
        // SwiftUI hierarchy. The default `.menu` style renders content as menu
        // items, which cannot lay out columns.
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            // The icon is glanced at without focus, so it carries only the two
            // distinctions that matter from across a room: something is wrong,
            // and do not trust this at a glance. The exact age lives in the
            // popover, where there is attention to read it.
            Image(systemName: model.status.showsErrorIcon
                ? "exclamationmark.triangle"
                : "square.grid.3x1.below.line.grid.1x2")
                .opacity(model.status.dimsMenuBarIcon ? 0.45 : 1)
        }
        .menuBarExtraStyle(.window)
    }
}
