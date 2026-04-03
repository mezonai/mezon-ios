import UIKit
import CoreLocation
import MapKit

final class ShareLocationConfirmViewController: UIViewController {

    var onSend: ((Double, Double) -> Void)?

    private let coordinate: CLLocationCoordinate2D
    private let channelLabel: String

    init(coordinate: CLLocationCoordinate2D, channelLabel: String) {
        self.coordinate = coordinate
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
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mv.setRegion(region, animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        mv.addAnnotation(pin)
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
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        lbl.numberOfLines = 1
        return lbl
    }()

    private lazy var cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Cancel", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        btn.addAction(UIAction { [weak self] _ in self?.handleCancel() }, for: .touchUpInside)
        return btn
    }()

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Send", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.addAction(UIAction { [weak self] _ in self?.handleSend() }, for: .touchUpInside)
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
        infoRow.addSubview(coordinateLabel)

        let buttonRow = UIView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonRow)
        buttonRow.addSubview(cancelButton)
        buttonRow.addSubview(sendButton)

        headerLabel.text = "Send this location to \(channelLabel)"
        coordinateLabel.text = "Coordinate (\(String(format: "%.6f", coordinate.latitude)), \(String(format: "%.6f", coordinate.longitude)))"

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

            coordinateLabel.leadingAnchor.constraint(equalTo: locationIconContainer.trailingAnchor, constant: 10),
            coordinateLabel.trailingAnchor.constraint(equalTo: infoRow.trailingAnchor),
            coordinateLabel.centerYAnchor.constraint(equalTo: infoRow.centerYAnchor),

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
        separatorView.backgroundColor = t.border
        cancelButton.setTitleColor(t.text, for: .normal)
        sendButton.setTitleColor(.systemBlue, for: .normal)
    }

    @objc private func handleCancel() {
        dismiss(animated: true)
    }

    private func handleSend() {
        onSend?(coordinate.latitude, coordinate.longitude)
        dismiss(animated: true)
    }
}
