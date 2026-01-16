#!/usr/bin/env swift

import Foundation

let threshold = 90
let verbose = CommandLine.arguments.contains("--verbose") || CommandLine.arguments.contains("-v")
let noSleep = CommandLine.arguments.contains("--no-sleep")

// Check for bypass
if ProcessInfo.processInfo.environment["CLAUDE_NO_LIMIT"] == "1" {
    if verbose { print("⚠️  Rate limit guard bypassed (CLAUDE_NO_LIMIT=1)") }
    exit(0)
}

// Read session key from environment
guard let sessionKey = ProcessInfo.processInfo.environment["CLAUDE_SESSION_KEY"] else {
    if verbose { print("⚠️  No CLAUDE_SESSION_KEY set - skipping rate limit check") }
    exit(0)
}

// Read org ID from environment
guard let orgId = ProcessInfo.processInfo.environment["CLAUDE_ORG_ID"] else {
    if verbose { print("⚠️  No CLAUDE_ORG_ID set - skipping rate limit check") }
    exit(0)
}

func fetchUsageData(sessionKey: String, orgId: String) async throws -> (utilization: Int, resetsAt: Date?) {
    guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
        throw NSError(domain: "ClaudeAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }

    var request = URLRequest(url: url)
    request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpMethod = "GET"
    request.timeoutInterval = 10

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw NSError(domain: "ClaudeAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch"])
    }

    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let fiveHour = json["five_hour"] as? [String: Any],
       let utilization = fiveHour["utilization"] as? Int {

        var resetDate: Date? = nil
        if let resetsAt = fiveHour["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetDate = formatter.date(from: resetsAt)
        }

        return (utilization, resetDate)
    }

    throw NSError(domain: "ClaudeAPI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
}

Task {
    do {
        let (utilization, resetsAt) = try await fetchUsageData(sessionKey: sessionKey, orgId: orgId)

        if verbose {
            print("✓ Usage: \(utilization)% (threshold: \(threshold)%)")
        }

        if utilization >= threshold && !noSleep {
            // Calculate sleep time until reset
            var sleepSeconds = 600 // Default 10 minutes

            if let resetDate = resetsAt {
                let secondsUntilReset = Int(resetDate.timeIntervalSinceNow) + 60 // Add 1 min buffer
                if secondsUntilReset > 0 {
                    sleepSeconds = secondsUntilReset
                }
            }

            let minutes = sleepSeconds / 60
            print("⚠️  Claude usage at \(utilization)% - sleeping \(minutes) minutes until reset...")

            // Actually sleep
            Thread.sleep(forTimeInterval: Double(sleepSeconds))
            print("✓ Resuming after rate limit cooldown")
        }

        exit(0)
    } catch {
        if verbose { print("⚠️  Error checking usage: \(error.localizedDescription)") }
        exit(0)
    }
}

RunLoop.main.run()
