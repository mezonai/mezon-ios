import UIKit

final class LanguageSettingsViewController: BaseViewController {

    private let languages = AppLanguage.allCases

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tv.dataSource = self
        tv.delegate   = self
        return tv
    }()

    override func setupUI() {
        navigationItem.largeTitleDisplayMode = .never
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func applyTheme() {
        title = L(L10n.Language.title)
        let t = UIColor.theme
        view.backgroundColor       = t.primary
        tableView.backgroundColor  = t.primary
        tableView.reloadData()
    }
}

extension LanguageSettingsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        languages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let lang = languages[indexPath.row]
        let t    = UIColor.theme

        var config = UIListContentConfiguration.cell()
        config.text                = lang.displayName
        config.textProperties.font = .systemFont(ofSize: 16.sf)
        config.textProperties.color = t.textStrong
        cell.contentConfiguration  = config
        cell.backgroundColor       = t.secondary
        cell.accessoryType         = lang == LanguageManager.shared.current ? .checkmark : .none
        cell.tintColor             = .mezonPrimary
        cell.selectionStyle        = .default
        return cell
    }
}

extension LanguageSettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        LanguageManager.shared.set(languages[indexPath.row])
        tableView.reloadData()
    }
}
