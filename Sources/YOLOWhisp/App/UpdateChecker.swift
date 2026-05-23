import Foundation

public final class GitHubUpdateChecker: UpdateChecking {
    public let repoOwner: String
    public let repoName: String
    public let currentVersion: String
    private let session: URLSession

    public private(set) var canCheckForUpdates: Bool = true
    public var onUpdateAvailable: ((String, URL) -> Void)?

    public init(repoOwner: String = "YOLOVibeCode", repoName: String = "yolowhisp",
                currentVersion: String = "0.1.0", session: URLSession = .shared) {
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.currentVersion = currentVersion
        self.session = session
    }

    public func checkForUpdates() {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        canCheckForUpdates = false
        let task = session.dataTask(with: request) { [weak self] data, _, error in
            defer { self?.canCheckForUpdates = true }

            guard let self = self, error == nil, let data = data else { return }

            struct Release: Decodable {
                let tag_name: String
                let html_url: String
            }

            guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return }

            let remoteVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if self.isVersion(remoteVersion, newerThan: self.currentVersion) {
                if let releaseURL = URL(string: release.html_url) {
                    self.onUpdateAvailable?(remoteVersion, releaseURL)
                }
            }
        }
        task.resume()
    }

    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
