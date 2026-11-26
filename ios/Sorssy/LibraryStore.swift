import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var sources: [SourceModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let catalogURL = URL(string: "https://raw.githubusercontent.com/albyatysjad74-art/sorssy/main/sorssy-sources.json")!

    func source(id: String) -> SourceModel? {
        sources.first { $0.id == id }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await fetch(catalogURL)
            let catalog = try JSONDecoder().decode(SourceCatalog.self, from: data)
            var refreshed: [SourceModel] = []
            for definition in catalog.sources {
                var item = SourceModel(definition: definition, document: nil, loadError: nil)
                do {
                    guard let url = URL(string: definition.url), url.scheme?.lowercased() == "https" else {
                        throw LibraryError.invalidURL
                    }
                    item.document = try JSONDecoder().decode(SourceDocument.self, from: await fetch(url))
                    if item.document?.apps == nil { throw LibraryError.invalidSource }
                } catch {
                    item.loadError = "تعذّر تحميل هذا المصدر. تحقق من الرابط أو حاول لاحقاً."
                }
                refreshed.append(item)
            }
            sources = refreshed
        } catch {
            errorMessage = "تعذّر تحميل قائمة المصادر. تحقق من اتصال الإنترنت ثم حدّث الصفحة."
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LibraryError.badResponse
        }
        return data
    }
}

private enum LibraryError: Error {
    case invalidURL
    case invalidSource
    case badResponse
}
