import SwiftUI
import Foundation



/// Codable struct for sending a message to the backend for cover text generation.
struct MessageRequest: Codable {
    let message: String
}

/// Codable struct for receiving cover and recovered text from the backend.
struct MessageResponse: Codable {
    let cover: String
    let recovered: String
}

/// Calls the backend API to generate a cover message for the given real message.
/// Returns the cover text via completion handler.
func generateCoverMessage(from realMessage: String, completion: @escaping (String?) -> Void) {
    guard let url = URL(string: "\(API.baseURL)/generate_cover") else {
        completion(nil)
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload = MessageRequest(message: realMessage)
    request.httpBody = try? JSONEncoder().encode(payload)

    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data = data, let raw = String(data: data, encoding: .utf8) {
            print("🐞 Raw generateCoverMessage response:", raw)
        }
        if let data = data,
           let response = try? JSONDecoder().decode(MessageResponse.self, from: data) {
            completion(response.cover)
        } else {
            completion(nil)
        }
    }.resume()
}
