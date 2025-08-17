import Foundation
import SwiftUI

/// Provides static functions to fetch message IDs and bodies from the Gmail API.
class GmailService {

    static func fetchEmailIDsFromSender(accessToken: String, senderEmail: String, completion: @escaping ([String]) -> Void) {
        // Gmail API query to find emails from specific sender
        let query = "from:\(senderEmail)"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(encodedQuery)&maxResults=10") else { // Reduced from 50 to 10
            print("❌ Invalid Gmail API URL")
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0 // Add timeout
        
        print("🔍 Fetching emails FROM: \(senderEmail)")
        print("📡 Gmail API URL: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Gmail API error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            // ENHANCED: Rate limit handling
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Gmail API Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 429 {
                    // Rate limited - store the retry time
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        
                        print("⏰ Gmail API Rate Limited: \(message)")
                        
                        // Extract retry time from error message
                        if let retryTimeString = extractRetryTime(from: message) {
                            UserDefaults.standard.set(retryTimeString, forKey: "gmailRateLimitUntil")
                            print("⏰ Rate limit stored until: \(retryTimeString)")
                        } else {
                            // Default 15 minute cooldown
                            let cooldownUntil = Date().addingTimeInterval(15 * 60)
                            let retryTimeString = ISO8601DateFormatter().string(from: cooldownUntil)
                            UserDefaults.standard.set(retryTimeString, forKey: "gmailRateLimitUntil")
                            print("⏰ Default rate limit cooldown until: \(retryTimeString)")
                        }
                    }
                    
                    completion([])
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    print("❌ Gmail API returned error status: \(httpResponse.statusCode)")
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Error response: \(responseString)")
                    }
                    completion([])
                    return
                }
            }
            
            guard let data = data else {
                print("❌ No data received from Gmail API")
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let messages = json["messages"] as? [[String: Any]] {
                        let ids = messages.compactMap { $0["id"] as? String }
                        print("✅ Found \(ids.count) emails from \(senderEmail)")
                        completion(ids)
                    } else {
                        print("📭 No messages found from \(senderEmail)")
                        completion([])
                    }
                } else {
                    print("❌ Invalid JSON response from Gmail API")
                    completion([])
                }
            } catch {
                print("❌ JSON parsing error: \(error.localizedDescription)")
                completion([])
            }
        }.resume()
    }

    // HELPER: Extract retry time from Gmail error message
    private static func extractRetryTime(from message: String) -> String? {
        // Look for pattern like "Retry after 2025-08-11T03:02:21.441Z"
        let pattern = "Retry after ([0-9T:\\-\\.Z]+)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        if let match = regex?.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.utf16.count)) {
            if let range = Range(match.range(at: 1), in: message) {
                return String(message[range])
            }
        }
        
        return nil
    }

    // ENHANCED: Backup function to fetch all recent emails if sender-specific fails
    static func fetchAllRecentEmails(accessToken: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=100&q=is:unread") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        print("🔍 Fetching all recent unread emails as fallback")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Gmail API error (fallback): \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("❌ No data received from Gmail API (fallback)")
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let messages = json["messages"] as? [[String: Any]] {
                    let ids = messages.compactMap { $0["id"] as? String }
                    print("✅ Found \(ids.count) unread emails (fallback)")
                    completion(ids)
                } else {
                    print("📭 No unread messages found (fallback)")
                    completion([])
                }
            } catch {
                print("❌ JSON parsing error (fallback): \(error.localizedDescription)")
                completion([])
            }
        }.resume()
    }
    
    /// Fetches the IDs of recent inbox messages using the Gmail API.
    static func fetchEmailIDs(accessToken: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=10&q=is:inbox") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion([])
                return
            }

            guard let data = data else {
                completion([])
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = json["messages"] as? [[String: Any]] else {
                completion([])
                return
            }

            let ids = messages.compactMap { $0["id"] as? String }
            completion(ids)
        }.resume()
    }

    /// Fetches the body, timestamp, sender, and recipient of a Gmail message by ID.

    // ENHANCED version of fetchEmailBody in GmailService.swift

    static func fetchEmailBody(
        id: String,
        token: String,
        completion: @escaping (String?, String?, String?, String?, [String: String]?) -> Void
    ) {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data else {
                completion(nil, nil, nil, nil, nil)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any] else {
                completion(nil, nil, nil, nil, nil)
                return
            }

            // Extract timestamp
            var timestampString: String?
            if let internalDateStr = json["internalDate"] as? String,
               let ms = Double(internalDateStr) {
                let date = Date(timeIntervalSince1970: ms / 1000)
                timestampString = ISO8601DateFormatter().string(from: date)
            }

            // CRITICAL: Extract headers including custom WindTexter headers
            var senderAddress: String?
            var recipientAddress: String?
            var customHeaders: [String: String] = [:]
            
            if let headers = payload["headers"] as? [[String: Any]] {
                print("📧 Processing \(headers.count) email headers...")
                
                for header in headers {
                    if let name = header["name"] as? String, let value = header["value"] as? String {
                        print("   Header: \(name) = \(value)")
                        
                        switch name {
                        case "From":
                            senderAddress = value
                        case "To":
                            recipientAddress = value
                        case "Delivered-To":
                            if recipientAddress == nil {
                                recipientAddress = value
                            }
                        // CRITICAL: Parse WindTexter custom headers
                        case "X-WindTexter-Sender":
                            customHeaders["realSender"] = value
                            print("   🎯 Found real sender: \(value)")
                        case "X-WindTexter-Sender-ID":
                            customHeaders["senderID"] = value
                            print("   🎯 Found sender ID: \(value)")
                        case "X-WindTexter-Chat-ID":
                            customHeaders["chatID"] = value
                            print("   🎯 Found chat ID: \(value)")
                        case "Reply-To":
                            customHeaders["replyTo"] = value
                            print("   🎯 Found reply-to: \(value)")
                        default:
                            break
                        }
                    }
                }
            }
            
            print("📧 Final parsing results:")
            print("   From: \(senderAddress ?? "nil")")
            print("   To: \(recipientAddress ?? "nil")")
            print("   WindTexter headers: \(customHeaders)")

            // Extract email body (existing logic)
            // Try to decode from parts first
            if let parts = payload["parts"] as? [[String: Any]] {
                for part in parts {
                    if let mimeType = part["mimeType"] as? String,
                       mimeType == "text/plain",
                       let body = part["body"] as? [String: Any],
                       let data64 = body["data"] as? String {
                        let clean = data64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                        if let decodedData = Data(base64Encoded: clean),
                           let decodedString = String(data: decodedData, encoding: .utf8) {
                            completion(decodedString, timestampString, senderAddress, recipientAddress, customHeaders)
                            return
                        }
                    }
                }
            }

            // Try fallback body
            if let body = payload["body"] as? [String: Any],
               let data64 = body["data"] as? String {
                let clean = data64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                if let decodedData = Data(base64Encoded: clean),
                   let decodedString = String(data: decodedData, encoding: .utf8) {
                    completion(decodedString, timestampString, senderAddress, recipientAddress, customHeaders)
                    return
                }
            }

            completion(nil, timestampString, senderAddress, recipientAddress, customHeaders)
        }.resume()
    }
}
