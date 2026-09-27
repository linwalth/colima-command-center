import Foundation

/// Fetches available k3s release versions from GitHub API.
/// Colima accepts any version matching https://github.com/k3s-io/k3s/releases
struct K3sVersions {
    static func fetch(currentVersion: String?, completion: @escaping ([String]) -> Void) {
        let url = URL(string: "https://api.github.com/repos/k3s-io/k3s/releases?per_page=100")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                // Network/API failure: still guarantee current version selectable.
                completion(merged([], current: currentVersion))
                return
            }
            let allTags = json.compactMap { $0["tag_name"] as? String }
            // Exclude release candidates (contain "-rc"): stable releases only
            // in the picker. RCs clutter the list and aren't typical daily-use.
            let stable = allTags.filter { !$0.contains("-rc") }
            completion(merged(stable.sorted(by: >), current: currentVersion))
        }.resume()
    }

    /// Guarantee the currently-running version is always present in the list,
    /// even if it fell out of the fetched page (older release) or the fetch
    /// failed. Insert sorted-newest-first so the picker highlights it.
    private static func merged(_ fetched: [String], current: String?) -> [String] {
        guard let cur = current, !cur.isEmpty, !fetched.contains(cur) else {
            return fetched
        }
        var result = fetched
        result.insert(cur, at: 0)
        return result
    }
}
