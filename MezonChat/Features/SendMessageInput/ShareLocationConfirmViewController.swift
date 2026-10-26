import UIKit
import CoreLocation
import MapKit

final class ShareLocationConfirmViewController: UIViewController {

    var onSend: ((Double, Double) -> Void)?

    private let channelLabel: String
    private let locationManager = CLLocationManager()
    private let pin = MKPointAnnotation()
    private var currentLocation: CLLocation?

    private static let recentLocationMaxAge: TimeInterval = 30
    private static let accuracyDecayPerSecond: CLLocationAccuracy = 2
    private static let minimumMapSpanMeters: CLLocationDistance = 500
    private static let fullAccuracyPurposeKey = "ShareLocation"

    init(channelLabel: String) {
        self.channelLabel = channelLabel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var backdropView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCancel))
        v.addGestureRecognizer(tap)
        return v
    }()

    private lazy var containerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        v.clipsToBounds = true
        return v
    }()

    private lazy var mapView: MKMapView = {
        let mv = MKMapView()
        mv.translatesAutoresizingMaskIntoConstraints = false
        mv.isUserInteractionEnabled = false
        return mv
    }()

    private lazy var headerLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 15, weight: .semibold)
        lbl.textAlignment = .center
        lbl.numberOfLines = 2
        return lbl
    }()

    private lazy var locationIconContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.44, alpha: 1)
        v.layer.cornerRadius = 20
        v.clipsToBounds = true

        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "location.fill", withConfiguration: config))
        iv.tintColor = .white
        iv.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    private lazy var coordinateLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 13)
        lbl.numberOfLines = 1
        return lbl
    }()

    private lazy var accuracyLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 12)
        lbl.numberOfLines = 1
        return lbl
    }()

    private lazy var locationTextStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [coordinateLabel, accuracyLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }()

    private lazy var cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(L(L10n.Common.cancel), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)
        return btn
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(L(L10n.ChannelMessages.shareLocationSend), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.addTarget(self, action: #selector(handleSendTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var separatorView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        applyTheme()
        startLocationUpdates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        locationManager.stopUpdatingLocation()
    }

    private func setupLayout() {
        view.addSubview(backdropView)
        view.addSubview(containerView)
        containerView.addSubview(headerLabel)
        containerView.addSubview(mapView)
        containerView.addSubview(separatorView)

        let infoRow = UIView()
        infoRow.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(infoRow)
        infoRow.addSubview(locationIconContainer)
        infoRow.addSubview(locationTextStack)

        let buttonRow = UIView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonRow)
        buttonRow.addSubview(cancelButton)
        buttonRow.addSubview(sendButton)

        headerLabel.text = L(L10n.ChannelMessages.shareLocationTitle, channelLabel)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            headerLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            mapView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            mapView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            mapView.heightAnchor.constraint(equalToConstant: 200),

            separatorView.topAnchor.constraint(equalTo: mapView.bottomAnchor),
            separatorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            infoRow.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 14),
            infoRow.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            infoRow.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            locationIconContainer.leadingAnchor.constraint(equalTo: infoRow.leadingAnchor),
            locationIconContainer.centerYAnchor.constraint(equalTo: infoRow.centerYAnchor),
            locationIconContainer.widthAnchor.constraint(equalToConstant: 40),
            locationIconContainer.heightAnchor.constraint(equalToConstant: 40),
            locationIconContainer.topAnchor.constraint(equalTo: infoRow.topAnchor),
            locationIconContainer.bottomAnchor.constraint(equalTo: infoRow.bottomAnchor),

            locationTextStack.leadingAnchor.constraint(equalTo: locationIconContainer.trailingAnchor, constant: 10),
            locationTextStack.trailingAnchor.constraint(equalTo: infoRow.trailingAnchor),
            locationTextStack.centerYAnchor.constraint(equalTo: infoRow.centerYAnchor),

            buttonRow.topAnchor.constraint(equalTo: infoRow.bottomAnchor, constant: 16),
            buttonRow.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            buttonRow.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            buttonRow.heightAnchor.constraint(equalToConstant: 44),

            cancelButton.leadingAnchor.constraint(equalTo: buttonRow.leadingAnchor),
            cancelButton.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
            cancelButton.widthAnchor.constraint(equalTo: buttonRow.widthAnchor, multiplier: 0.5, constant: -4),

            sendButton.trailingAnchor.constraint(equalTo: buttonRow.trailingAnchor),
            sendButton.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            sendButton.bottomAnchor.constraint(equalTo: buttonRow.bottomAnchor),
            sendButton.widthAnchor.constraint(equalTo: buttonRow.widthAnchor, multiplier: 0.5, constant: -4),
        ])
    }

    private func applyTheme() {
        let t = UIColor.theme
        containerView.backgroundColor = t.secondary
        headerLabel.textColor = t.textStrong
        coordinateLabel.textColor = t.textDisabled
        accuracyLabel.textColor = t.textDisabled
        separatorView.backgroundColor = t.border
        cancelButton.setTitleColor(t.text, for: .normal)
        sendButton.setTitleColor(.systemBlue, for: .normal)
        sendButton.setTitleColor(t.textDisabled, for: .disabled)
    }

    private func startLocationUpdates() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        if let cached = locationManager.location, isUsableLocation(cached) {
            currentLocation = cached
        }
        renderLocation()
        if #available(iOS 14.0, *), locationManager.accuracyAuthorization == .reducedAccuracy {
            locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.fullAccuracyPurposeKey)
        }
        locationManager.startUpdatingLocation()
    }

    private func isUsableLocation(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && abs(location.timestamp.timeIntervalSinceNow) <= Self.recentLocationMaxAge
    }

    private func isPreferredLocation(_ candidate: CLLocation, over current: CLLocation) -> Bool {
        let elapsed = max(0, candidate.timestamp.timeIntervalSince(current.timestamp))
        return candidate.horizontalAccuracy <= current.horizontalAccuracy + elapsed * Self.accuracyDecayPerSecond
    }

    private func applyLocation(_ location: CLLocation) {
        guard isUsableLocation(location) else { return }
        if let current = currentLocation, !isPreferredLocation(location, over: current) { return }
        currentLocation = location
        renderLocation()
    }

    private func renderLocation() {
        guard let location = currentLocation else {
            coordinateLabel.text = L(L10n.ChannelMessages.shareLocationLocating)
            accuracyLabel.isHidden = true
            sendButton.isEnabled = false
            return
        }
        let coordinate = location.coordinate
        pin.coordinate = coordinate
        if mapView.annotations.isEmpty {
            mapView.addAnnotation(pin)
        }
        let span = max(Self.minimumMapSpanMeters, location.horizontalAccuracy * 3)
        mapView.setRegion(
            MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span),
            animated: true
        )
        coordinateLabel.text = L(
            L10n.ChannelMessages.shareLocationCoordinate,
            String(format: "%.6f", coordinate.latitude),
            String(format: "%.6f", coordinate.longitude)
        )
        accuracyLabel.text = L(L10n.ChannelMessages.shareLocationAccuracy, Self.distanceText(location.horizontalAccuracy))
        accuracyLabel.isHidden = false
        sendButton.isEnabled = true
    }

    private static func distanceText(_ meters: CLLocationAccuracy) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    @objc private func handleCancel() {
        dismiss(animated: true)
    }

    @objc private func handleSendTapped() { handleSend() }

    private func handleSend() {
        guard let coordinate = currentLocation?.coordinate else { return }
        onSend?(coordinate.latitude, coordinate.longitude)
        dismiss(animated: true)
    }
}

extension ShareLocationConfirmViewController: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            applyLocation(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied {
            manager.stopUpdatingLocation()
        }
    }
}
