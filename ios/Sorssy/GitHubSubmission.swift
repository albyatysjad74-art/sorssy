import Foundation

enum GitHubSubmission {
    private static let issuesURL = URL(string: "https://github.com/albyatysjad74-art/sorssy/issues/new")!

    static func issueURL(title: String, payload: [String: Any]) -> URL? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let body = String(data: data, encoding: .utf8),
              var components = URLComponents(url: issuesURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
