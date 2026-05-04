import Foundation

struct Analytics {
    static let endpoint = "https://script.google.com/macros/s/AKfycbww96AR0n9Aq8V2aQNmKuQs-BUljeuTWdKQL259NRX4IxZdO6I1s_9P9h_Omz-HqPRlqw/exec"

    static func send(event: String) {
        guard let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get device and OS info
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceName = Host.current().localizedName ?? "Unknown Mac"
        let modelIdentifier = getMacModel() // custom function below
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let payload: [String: String] = [
            "event": event,
            "deviceName": deviceName,
            "modelIdentifier": modelIdentifier,
            "osVersion": osVersion,
            "appVersion": appVersion
        ]

        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req).resume()

        print("📤 Sent event:", event)
    }

    // Helper to get the Mac model (e.g. "MacBookAir10,1")
    private static func getMacModel() -> String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
