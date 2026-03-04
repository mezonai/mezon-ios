import UIKit
import Combine

extension UIControl {
    func publisher(for events: UIControl.Event) -> AnyPublisher<Void, Never> {
        UIControlPublisher(control: self, events: events).eraseToAnyPublisher()
    }

    var tapPublisher: AnyPublisher<Void, Never> {
        publisher(for: .touchUpInside)
    }
}


private struct UIControlPublisher: Publisher {
    typealias Output = Void
    typealias Failure = Never

    let control: UIControl
    let events: UIControl.Event

    func receive<S: Subscriber>(subscriber: S) where S.Input == Void, S.Failure == Never {
        let subscription = UIControlSubscription(subscriber: subscriber, control: control, events: events)
        subscriber.receive(subscription: subscription)
    }
}

private final class UIControlSubscription<S: Subscriber>: Subscription where S.Input == Void, S.Failure == Never {
    private var subscriber: S?
    private let control: UIControl

    init(subscriber: S, control: UIControl, events: UIControl.Event) {
        self.subscriber = subscriber
        self.control = control
        control.addTarget(self, action: #selector(handleEvent), for: events)
    }

    func request(_ demand: Subscribers.Demand) {}

    func cancel() {
        subscriber = nil
        control.removeTarget(self, action: #selector(handleEvent), for: .allEvents)
    }

    @objc private func handleEvent() {
        _ = subscriber?.receive(())
    }
}
