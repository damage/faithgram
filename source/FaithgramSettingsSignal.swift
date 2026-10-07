import Foundation
import SwiftSignalKit

public func faithgramSettingsChanges() -> Signal<Void, NoError> {
    return Signal { subscriber in
        subscriber.putNext(())
        let observer = NotificationCenter.default.addObserver(forName: FaithgramPreferences.changed, object: nil, queue: nil) { _ in subscriber.putNext(()) }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}
