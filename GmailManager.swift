// CORRECTED GmailManager.swift - Fixed to work with updated GmailService

import Foundation
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

/// Manages Gmail integration: fetching, decoding, and storing messages from Gmail.
class GmailManager {
    
    /// NEW: Fetches Gmail messages FROM a specific sender to the current user's inbox
    static func fetchAndStoreMessagesFromSender(currentUserEmail: String, senderEmail: String, chat: Chat) {
        guard !currentUserEmail.isEmpty,
              !senderEmail.isEmpty,
              let accessToken = UserDefaults.standard.string(forKey: "gmailAccessToken") else {
            print("❌ Missing email parameters or no access token")
            return
        }

        print("🔍 Checking \(currentUserEmail)'s inbox for messages FROM \(senderEmail)")

        // Option 1: Try to use the sender-specific query
        GmailService.fetchEmailIDsFromSender(
            accessToken: accessToken,
            senderEmail: senderEmail
        ) { ids in
            print("📧 Found \(ids.count) email IDs from sender query")
            
            if ids.isEmpty {
                // Option 2: Fallback to general fetch and filter client-side
                print("🔄 No messages from sender query, trying general fetch...")
                GmailService.fetchEmailIDs(accessToken: accessToken) { allIds in
                    print("📧 Found \(allIds.count) total email IDs, filtering for sender...")
                    processEmailsFromSender(
                        ids: allIds,
                        accessToken: accessToken,
                        currentUserEmail: currentUserEmail,
                        senderEmail: senderEmail,
                        chat: chat
                    )
                }
            } else {
                // Process the sender-specific results
                processEmailsFromSender(
                    ids: ids,
                    accessToken: accessToken,
                    currentUserEmail: currentUserEmail,
                    senderEmail: senderEmail,
                    chat: chat
                )
            }
        }
    }

    /// Helper function to process emails from a specific sender
    private static func processEmailsFromSender(
        ids: [String],
        accessToken: String,
        currentUserEmail: String,
        senderEmail: String,
        chat: Chat
    ) {
        for id in ids {
            // FIXED: Added the 5th parameter (customHeaders)
            GmailService.fetchEmailBody(id: id, token: accessToken) { body, timestampString, sender, recipient, customHeaders in
                guard let body = body, !body.isEmpty else {
                    return
                }

                // VALIDATION: Ensure this message is actually FROM the expected sender
                guard let sender = sender?.lowercased() else {
                    print("❌ No sender information")
                    return
                }
                
                // Check if sender contains the expected email OR is from WindTexter service
                let isFromExpectedSender = sender.contains(senderEmail.lowercased()) ||
                                         sender.contains("windtexter@gmail.com")
                
                guard isFromExpectedSender else {
                    print("❌ Message not from expected sender \(senderEmail) (actual: \(sender))")
                    return
                }
                
                // VALIDATION: Ensure this message is TO the current user
                guard let recipient = recipient?.lowercased(),
                      recipient.contains(currentUserEmail.lowercased()) else {
                    print("❌ Message not sent to current user \(currentUserEmail)")
                    return
                }
                
                // Don't process messages sent by the current user
                if sender.contains(currentUserEmail.lowercased()) {
                    print("❌ Message sent by current user, skipping")
                    return
                }

                print("✅ Processing message FROM \(sender) TO \(recipient)")
                print("📧 Custom headers: \(customHeaders ?? [:])")

                let key = "savedMessages-\(chat.id.uuidString)"
                var messages: [Message] = []

                if let data = UserDefaults.standard.data(forKey: key),
                   let decoded = try? JSONDecoder().decode([Message].self, from: data) {
                    messages = decoded

                    // Check for duplicates
                    if messages.contains(where: { $0.coverText == body || $0.realText == body }) {
                        print("🔄 Duplicate message found, skipping")
                        return
                    }
                }

                decodeCoverChunks([body]) { decodedText in
                    let realText = decodedText ?? body
                    let timestamp = timestampString ?? ISO8601DateFormatter().string(from: Date())

                    let newMessage = Message(
                        realText: realText,
                        coverText: body,
                        isSentByCurrentUser: false,  // This is a received message
                        timestamp: timestamp,
                        deliveryPath: "email"
                    )

                    // IMPROVED: Use sender ID from headers if available, otherwise use sender email
                    newMessage.senderID = customHeaders?["senderID"] ?? "sender_\(senderEmail.lowercased())"

                    messages.append(newMessage)

                    if let encoded = try? JSONEncoder().encode(messages) {
                        UserDefaults.standard.set(encoded, forKey: key)
                    }
                    
                    print("✅ Stored new message from \(senderEmail) for \(chat.name)")
                    
                    // Notify the message store
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("NewMessageReceived"), object: chat)
                    }
                }
            }
        }
    }

    /// EXISTING: Keep the old function for backward compatibility but mark as deprecated
    @available(*, deprecated, message: "Use fetchAndStoreMessagesFromSender instead")
    static func fetchAndStoreMessages(for chat: Chat) {
        guard let chatEmail = chat.email,
              !chatEmail.isEmpty,
              let accessToken = UserDefaults.standard.string(forKey: "gmailAccessToken") else {
            print("❌ Missing email for chat \(chat.name) or no access token")
            return
        }

        print("🔍 Checking messages for chat: \(chat.name) (\(chatEmail))")

        GmailService.fetchEmailIDs(accessToken: accessToken) { ids in
            print("📧 Found \(ids.count) email IDs")

            for id in ids {
                // FIXED: Added the 5th parameter (customHeaders)
                GmailService.fetchEmailBody(id: id, token: accessToken) { body, timestampString, sender, recipient, customHeaders in
                    guard let body = body, !body.isEmpty else {
                        return
                    }

                    guard let sender = sender?.lowercased(),
                          sender.contains("windtexter@gmail.com") else {
                        print("❌ Message not from WindTexter service")
                        return
                    }
                    
                    guard let recipient = recipient?.lowercased(),
                          recipient.contains(chatEmail.lowercased()) else {
                        print("❌ Message not intended for \(chatEmail), skipping")
                        return
                    }
                    
                    if sender.contains(chatEmail.lowercased()) {
                        print("❌ Message sent by current user, skipping")
                        return
                    }

                    print("✅ Processing message for \(chat.name): sender=\(sender), recipient=\(recipient)")
                    print("📧 Custom headers: \(customHeaders ?? [:])")

                    let key = "savedMessages-\(chat.id.uuidString)"
                    var messages: [Message] = []

                    if let data = UserDefaults.standard.data(forKey: key),
                       let decoded = try? JSONDecoder().decode([Message].self, from: data) {
                        messages = decoded

                        if messages.contains(where: { $0.coverText == body || $0.realText == body }) {
                            print("🔄 Duplicate message found, skipping")
                            return
                        }
                    }

                    decodeCoverChunks([body]) { decodedText in
                        let realText = decodedText ?? body
                        let timestamp = timestampString ?? ISO8601DateFormatter().string(from: Date())

                        let newMessage = Message(
                            realText: realText,
                            coverText: body,
                            isSentByCurrentUser: false,
                            timestamp: timestamp,
                            deliveryPath: "email"
                        )

                        // IMPROVED: Use sender ID from headers if available
                        newMessage.senderID = customHeaders?["senderID"] ?? "windtexter_service"
                        messages.append(newMessage)

                        if let encoded = try? JSONEncoder().encode(messages) {
                            UserDefaults.standard.set(encoded, forKey: key)
                        }
                        
                        print("✅ Stored new message for \(chat.name)")
                    }
                }
            }
        }
    }

    /// EXISTING: Keep the existing decode function
    static func decodeCoverChunks(_ covers: [String], completion: @escaping (String?) -> Void) {
        guard let bitString = covers.first else {
            completion(nil)
            return
        }

        let bits: [Int] = bitString.compactMap { char in
            if char == "0" { return 0 }
            else if char == "1" { return 1 }
            else { return nil }
        }

        guard !bits.isEmpty else {
            print("Empty or invalid bit sequence.")
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "bit_sequence": bits,
            "compression_method": "utf8"
        ]

        guard let url = URL(string: "\(API.baseURL)/decode_cover_chunks") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let decoded = json["decoded_text"] as? String {
                completion(decoded)
            } else {
                print("❌ Failed to parse decoded text from response")
                completion(nil)
            }
        }.resume()
    }
}
