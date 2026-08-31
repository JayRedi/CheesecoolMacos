import Foundation

@MainActor
final class LifecycleNotificationRouter {
    private let notificationCenter: NotificationCenter
    private let sleepNotification: Notification.Name
    private let wakeNotification: Notification.Name
    private let onSleep: () -> Void
    private let onWake: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        notificationCenter: NotificationCenter,
        sleepNotification: Notification.Name,
        wakeNotification: Notification.Name,
        onSleep: @escaping () -> Void,
        onWake: @escaping () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.sleepNotification = sleepNotification
        self.wakeNotification = wakeNotification
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func start() {
        guard observers.isEmpty else { return }
        observers = [
            notificationCenter.addObserver(forName: sleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.onSleep() }
            },
            notificationCenter.addObserver(forName: wakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.onWake() }
            }
        ]
    }

    func stop() {
        for observer in observers { notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
