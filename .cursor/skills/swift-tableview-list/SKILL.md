---
name: swift-tableview-list
description: Implement UITableView list với binding Combine. Use when adding message list, channel list, or any scrollable list screen.
---

# UITableView List Pattern

## Setup

```swift
lazy var tableView: UITableView = {
    let tv = UITableView(frame: .zero, style: .plain)
    tv.translatesAutoresizingMaskIntoConstraints = false
    tv.backgroundColor = .clear
    tv.rowHeight = UITableView.automaticDimension
    tv.estimatedRowHeight = 60
    tv.register(CellClass.self, forCellReuseIdentifier: CellClass.reuseId)
    tv.dataSource = self
    tv.delegate = self
    tv.tableFooterView = UIView()
    return tv
}()
```

## Binding

```swift
viewModel.$items
    .receive(on: DispatchQueue.main)
    .sink { [weak self] _ in
        self?.tableView.reloadData()
        self?.tableView.layoutIfNeeded()
    }
    .store(in: &cancellables)
```

## Cell

- `configure(model:)` - set data, gọi applyTheme()
- Constraint chain đầy đủ cho automaticDimension (top → bottom)

## Scroll to bottom

```swift
let last = IndexPath(row: items.count - 1, section: 0)
tableView.scrollToRow(at: last, at: .bottom, animated: false)
```
