import Foundation

@Observable
@MainActor
final class UpdateChecker {
    var availableVersion: String?
    var downloadURL: String?

    private let current: String
    private let apiURL = URL(string: "https://api.github.com/repos/lumenworksco/Tokn/releases/latest")!

    init() {
        current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // Returns (version, downloadURL) if a newer release exists, nil otherwise.
    func check() async -> (version: String, url: String)? {
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag  = json["tag_name"] as? String else { return nil }
        let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(remote, than: current) else { return nil }
        let url = (json["assets"] as? [[String: Any]])?.first?["browser_download_url"] as? String ?? ""
        availableVersion = remote
        downloadURL = url
        return (remote, url)
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator:  ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
