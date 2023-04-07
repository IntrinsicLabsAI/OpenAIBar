//
//  AppMain.swift
//  OpenAIBar
//
//  Created by Andrew Duffy on 4/2/23.
//

import SwiftUI
import os

@main
struct OpenAIBarApp: App {
    @StateObject var appState = OpenAIBarAppModel()
    
    private var lastRefreshedFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt
    }()
    
    var body: some Scene {
        MenuBarExtra {
            if let lastRefresh = appState.lastRefresh {
                let shortDate = lastRefreshedFormatter.string(from: lastRefresh)
                Text("Last Refreshed: \(shortDate)")
            }
            Divider()
            Text("👋 from Stallion Labs")
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            HStack {
                Image("icon")
                switch appState.data {
                case .notLoggedIn:
                    Text("Please put your token in ~/.oaitoken to login")
                case .loading:
                    Text("Loading...")
                case .fail:
                    Text("Failed")
                case .success(let data):
                    let spend = data.total_usage.rounded() / 100.0
                    let spendStr = String(format: "%0.2f", spend)
                    Text("$\(spendStr)")
                }
            }
        }
    }
}

enum LoadingState<T> {
    case notLoggedIn
    case loading
    case success(data: T)
    case fail(theError: Error)
}

class OpenAIBarAppModel: ObservableObject {
    private static var apiFile = ".oaitoken"

    @Published var data: LoadingState<OpenAIBillingUsageResponse>
    @Published var lastRefresh: Date?
    
    private var timer: Timer?
    private var token: OpenAIToken?
    
    
    init() {
        if let foundToken = OpenAIBarAppModel.tryLoginFromFile() {
            token = foundToken
            data = .loading
        } else {
            data = .notLoggedIn
        }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task {
                await self.refresh()
            }
        }
    }

    private let formatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
    
    func refresh() async {
        guard let apiKey = (token ?? OpenAIBarAppModel.tryLoginFromFile())?.apiKey else {
            print("Not logged in yet")
            return
        }
        let (startDate, endDate) = calculateStartEnd()
        do {
            let result = try await querySpend(startDate: startDate, endDate: endDate, token: apiKey)
            DispatchQueue.main.async {
                self.data = .success(data: result)
                self.lastRefresh = Date()
            }
        } catch {
            DispatchQueue.main.async {
                self.data = .fail(theError: error)
                self.lastRefresh = Date()
            }
        }
    }

    static func tryLoginFromFile() -> OpenAIToken? {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: apiFile, directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard let contents = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else {
                print("Token was not found in contents of file")
                return nil
            }
            
            return OpenAIToken(apiKey: String(decoding: contents, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        print("File \(url) does not exist")
        return nil
    }

    private func querySpend(startDate: String, endDate: String, token: String) async throws -> OpenAIBillingUsageResponse {
        let url = URL(string: "https://api.openai.com/dashboard/billing/usage")?.appending(
            queryItems: [
                URLQueryItem(name: "start_date", value: startDate),
                URLQueryItem(name: "end_date", value: endDate),
            ])
        var request = URLRequest(url: url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CustomError(reason: "Received fail response")
        }
        let decoder = JSONDecoder()
        let result = try decoder.decode(OpenAIBillingUsageResponse.self, from: data)
        return result
    }

    private func calculateStartEnd() -> (String, String) {
        let now = Date()
        var startComponents = Calendar.current.dateComponents([.year, .month, .day], from: now)
        startComponents.day = 1

        let tomorrow = now.addingTimeInterval(TimeInterval(86_400))
        let startDate = formatter.string(from: Calendar.current.date(from: startComponents)!)
        let endDate = formatter.string(from: tomorrow)

        return (startDate, endDate)
    }
}

struct OpenAIBillingUsageResponse: Codable {
    var total_usage: Float
}

struct CustomError: Error {
    var reason: String
}

struct OpenAIToken {
    var apiKey: String
}
