import Foundation

struct SourceCatalog: Decodable {
    let sources: [SourceDefinition]
}

struct SourceDefinition: Decodable, Identifiable {
    let catalogID: String?
    let name: String?
    let subtitle: String?
    let iconURL: String?
    let url: String
    let editable: Bool?

    var id: String { catalogID ?? url }
    var canEdit: Bool { editable == true }

    enum CodingKeys: String, CodingKey {
        case catalogID = "id"
        case name, subtitle, iconURL, url, editable
    }
}

struct SourceDocument: Decodable {
    let name: String?
    let subtitle: String?
    let iconURL: String?
    let apps: [CatalogApp]?
}

struct SourceModel: Identifiable {
    let definition: SourceDefinition
    var document: SourceDocument?
    var loadError: String?

    var id: String { definition.id }
    var name: String { definition.name ?? document?.name ?? "مصدر تطبيقات" }
    var subtitle: String { definition.subtitle ?? document?.subtitle ?? "" }
    var iconURL: String? { definition.iconURL ?? document?.iconURL }
    var apps: [CatalogApp] { document?.apps ?? [] }
    var canEdit: Bool { definition.canEdit }
}

struct CatalogApp: Decodable, Identifiable {
    let name: String?
    let bundleIdentifier: String?
    let iconURL: String?
    let localizedDescription: String?
    let category: String?
    let version: String?
    let versionDate: String?
    let downloadURL: String?
    let size: Double?
    let versions: [AppVersion]?

    var id: String { downloadURL ?? "\(bundleIdentifier ?? "app"): \(name ?? "")" }
}

struct AppVersion: Decodable, Identifiable {
    let downloadURL: String?
    let version: String?
    let date: String?
    let size: Double?

    var id: String { "\(version ?? ""): \(downloadURL ?? "")" }
}

struct IndexedApp: Identifiable {
    let index: Int
    let app: CatalogApp
    var id: Int { index }
}

struct AppFields {
    var name: String
    var bundleIdentifier: String
    var version: String
    var category: String
    var iconURL: String
    var downloadURL: String
    var sizeMB: String
    var description: String

    init(app: CatalogApp? = nil) {
        name = app?.name ?? ""
        bundleIdentifier = app?.bundleIdentifier ?? ""
        version = app?.version ?? ""
        category = app?.category ?? "أخرى"
        iconURL = app?.iconURL ?? ""
        downloadURL = app?.downloadURL ?? ""
        sizeMB = app?.size.map { String(format: "%.1f", $0 / 1_048_576) } ?? ""
        description = app?.localizedDescription ?? ""
    }

    var isValid: Bool {
        let bundlePattern = "^[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)+$"
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 100
            && bundleIdentifier.count <= 150
            && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && version.count <= 50
            && category.count <= 50
            && bundleIdentifier.range(of: bundlePattern, options: .regularExpression) != nil
            && Self.isHTTPS(iconURL)
            && iconURL.count <= 2048
            && Self.isHTTPS(downloadURL)
            && downloadURL.count <= 2048
            && description.count <= 5000
            && (sizeMB.isEmpty || (Double(sizeMB).map { $0 > 0 && $0 <= 953_674 } ?? false))
    }

    var issueValues: [String: Any] {
        var values: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "bundleIdentifier": bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            "version": version.trimmingCharacters(in: .whitespacesAndNewlines),
            "category": category.trimmingCharacters(in: .whitespacesAndNewlines),
            "iconURL": iconURL.trimmingCharacters(in: .whitespacesAndNewlines),
            "downloadURL": downloadURL.trimmingCharacters(in: .whitespacesAndNewlines),
            "localizedDescription": description.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let megabytes = Double(sizeMB), megabytes > 0 {
            values["size"] = Int((megabytes * 1_048_576).rounded())
        }
        return values
    }

    static func isHTTPS(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), components.scheme?.lowercased() == "https", components.host != nil else {
            return false
        }
        return components.user == nil && components.password == nil
    }
}
