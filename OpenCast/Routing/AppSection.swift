enum AppSection: String, CaseIterable, Identifiable {
    case library
    case downloads
    case settings
    case search

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .library:
            "Library"
        case .downloads:
            "Downloads"
        case .settings:
            "Settings"
        case .search:
            "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "books.vertical"
        case .downloads:
            "arrow.down.circle"
        case .settings:
            "gearshape"
        case .search:
            "magnifyingglass"
        }
    }
}
