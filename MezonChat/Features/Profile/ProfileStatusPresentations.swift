import UIKit

func makeProfileOptionRadioImage(selected: Bool, diameter: CGFloat = 20) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
    return renderer.image { _ in
        let outerRect = CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)
        let outer = UIBezierPath(ovalIn: outerRect)

        if selected {
            UIColor.outgoingBubble.setFill()
            outer.fill()
            let innerDiameter = diameter * 0.46
            let innerRect = CGRect(
                x: (diameter - innerDiameter) / 2,
                y: (diameter - innerDiameter) / 2,
                width: innerDiameter,
                height: innerDiameter
            )
            let inner = UIBezierPath(ovalIn: innerRect)
            UIColor.white.setFill()
            inner.fill()
        } else {
            UIColor.mezonTextStrong.setStroke()
            outer.lineWidth = 1.6
            outer.stroke()
        }
    }
}

final class ProfileSheetPresenceCell: UITableViewCell {
    static let reuseId = "ProfileSheetPresenceCell"

    private let iconView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let radioView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLbl: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .regular)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .mezonPrimary
        selectionStyle = .none
        contentView.addSubview(iconView)
        contentView.addSubview(titleLbl)
        contentView.addSubview(radioView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            titleLbl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: radioView.leadingAnchor, constant: -10.sw),

            radioView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            radioView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            radioView.widthAnchor.constraint(equalToConstant: 22),
            radioView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, icon: UIImage?, selected: Bool) {
        titleLbl.text = title
        iconView.image = icon
        radioView.image = makeProfileOptionRadioImage(selected: selected)
    }
}

final class ProfileSheetCustomStatusCell: UITableViewCell {
    static let reuseId = "ProfileSheetCustomStatusCell"

    private let iconView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLbl: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf, weight: .regular)
        l.textColor = .mezonTextStrong
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let clearBtn: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .mezonPrimary
        selectionStyle = .default
        contentView.addSubview(iconView)
        contentView.addSubview(titleLbl)
        contentView.addSubview(clearBtn)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            titleLbl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLbl.trailingAnchor.constraint(lessThanOrEqualTo: clearBtn.leadingAnchor, constant: -8.sw),

            clearBtn.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            clearBtn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 28),
            clearBtn.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, icon: UIImage?, showClear: Bool, clearTarget: Any?, clearAction: Selector) {
        titleLbl.text = title
        iconView.image = icon
        clearBtn.isHidden = !showClear
        clearBtn.removeTarget(nil, action: nil, for: .allEvents)
        if showClear {
            let cfg = MezonSymbolConfiguration(pointSize: 16, weight: .regular)
            clearBtn.setImage(UIImage.mezonSystemImage("xmark.circle.fill", withConfiguration: cfg), for: .normal)
            clearBtn.tintColor = .mezonTextPrimary
            clearBtn.addTarget(clearTarget, action: clearAction, for: .touchUpInside)
        } else {
            clearBtn.setImage(nil, for: .normal)
        }
    }
}

