// FIXED BackendAPI.swift - Add new function for conversation messages

import Foundation
import UIKit

/// Provides functions for communicating with the backend API (fetching messages, etc.).
class BackendAPI {
    

    static func fetchConversationMessages(
        for path: String,
        currentUserEmail: String,
        chatPartnerEmail: String,
        chatID: UUID,
        completion: @escaping ([Message]) -> Void
    ) {
        let normalizedPath = path.replacingOccurrences(of: "send_", with: "").lowercased()
        guard let url = URL(string: "\(API.baseURL)/fetch_conversation_messages") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let currentDeviceID = DeviceIDManager.shared.deviceID
        let body: [String: Any] = [
            "delivery_path": normalizedPath,
            "current_user_email": currentUserEmail.lowercased(),
            "chat_partner_email": chatPartnerEmail.lowercased(),
            "device_id": currentDeviceID,
            "chat_id": chatID.uuidString
        ]
        
        print("🔍 FETCH CONVERSATION REQUEST:")
        print("   delivery_path: '\(normalizedPath)'")
        print("   current_user_email: '\(currentUserEmail)'")
        print("   chat_partner_email: '\(chatPartnerEmail)'")
        print("   device_id: '\(currentDeviceID)'")
        print("   chat_id: '\(chatID.uuidString)'")
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                if let rawMessages = json?["messages"] as? [[String: Any]] {
                    
                    let currentUserID = DeviceIDManager.shared.deviceID
                    let messages = rawMessages.compactMap { messageDict -> Message? in
                        return parseBackendMessage(messageDict, currentUserID: currentUserID, currentUserEmail: currentUserEmail, chatPartnerEmail: chatPartnerEmail)
                    }
                    
                    print("🔄 Parsed \(rawMessages.count) raw messages to \(messages.count) Message objects for conversation")
                    
                    DispatchQueue.main.async {
                        completion(messages)
                    }
                } else {
                    print("❌ No 'messages' key found in response")
                    DispatchQueue.main.async { completion([]) }
                }
            } catch {
                print("❌ JSON decode error: \(error)")
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    /// EXISTING: Keep the old function for backward compatibility
    static func fetchMessages(for path: String, chatID: UUID? = nil, chatEmail: String? = nil, completion: @escaping ([Message]) -> Void) {
        let normalizedPath = path.replacingOccurrences(of: "send_", with: "").lowercased()
        guard let url = URL(string: "\(API.baseURL)/fetch_messages") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let currentDeviceID = DeviceIDManager.shared.deviceID
        var body: [String: Any] = [
            "delivery_path": normalizedPath,
            "device_id": currentDeviceID
        ]
        
        if let chatID = chatID {
            body["chat_id"] = chatID.uuidString
        }
        if let chatEmail = chatEmail {
            body["recipient_email"] = chatEmail.lowercased()
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                if let rawMessages = json?["messages"] as? [[String: Any]] {
                    
                    let currentUserID = DeviceIDManager.shared.deviceID
                    let messages = rawMessages.compactMap { messageDict -> Message? in
                        return parseBackendMessage(messageDict, currentUserID: currentUserID, expectedChatEmail: chatEmail)
                    }
                    
                    DispatchQueue.main.async {
                        completion(messages)
                    }
                } else {
                    DispatchQueue.main.async { completion([]) }
                }
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    /// IMPROVED: Enhanced message parsing for conversation context
    private static func parseBackendMessage(
        _ messageDict: [String: Any],
        currentUserID: String,
        currentUserEmail: String? = nil,
        chatPartnerEmail: String? = nil,
        expectedChatEmail: String? = nil
    ) -> Message? {
        guard let idString = messageDict["id"] as? String,
              let uuid = UUID(uuidString: idString),
              let timestamp = messageDict["timestamp"] as? String else {
            print("❌ Missing required fields in backend message")
            return nil
        }
        
        // Parse text fields (handle both camelCase and snake_case)
        let realText = messageDict["realText"] as? String ?? messageDict["real_text"] as? String
        let coverText = messageDict["coverText"] as? String ?? messageDict["cover_text"] as? String
        let rawPath = messageDict["delivery_path"] as? String ?? "email"
        let deliveryPath = normalizeDeliveryPath(rawPath)
        let senderID = messageDict["sender_id"] as? String
        let bitCount = messageDict["bit_count"] as? Int
        let isAutoReply = messageDict["is_auto_reply"] as? Bool ?? false
        
        // Parse message routing information
        let recipientEmail = messageDict["recipient_email"] as? String ?? messageDict["to_email"] as? String
        let senderEmail = messageDict["sender_email"] as? String ?? messageDict["from_email"] as? String
        
        // Parse image data from backend
        var imageData: Data? = nil
        if let imageBase64String = messageDict["imageData"] as? String ?? messageDict["image_data"] as? String,
           !imageBase64String.isEmpty {
            imageData = Data(base64Encoded: imageBase64String)
            if let imageData = imageData {
                print("📸 Parsed image data from backend: \(imageData.count) bytes")
            } else {
                print("⚠️ Failed to decode base64 image data")
            }
        }
        
        // IMPROVED: Better validation for conversation context
        if let currentUserEmail = currentUserEmail, let chatPartnerEmail = chatPartnerEmail {
            // Validate this message belongs to the conversation between currentUser and chatPartner
            let currentEmailLower = currentUserEmail.lowercased()
            let partnerEmailLower = chatPartnerEmail.lowercased()
            let recipientLower = recipientEmail?.lowercased() ?? ""
            let senderLower = senderEmail?.lowercased() ?? ""
            
            let isCurrentUserToPartner = (senderLower.contains(currentEmailLower) && recipientLower.contains(partnerEmailLower))
            let isPartnerToCurrentUser = (senderLower.contains(partnerEmailLower) && recipientLower.contains(currentEmailLower))
            
            if !isCurrentUserToPartner && !isPartnerToCurrentUser {
                print("❌ Message doesn't belong to conversation between \(currentEmailLower) and \(partnerEmailLower)")
                return nil
            }
        }
        
        // Determine ownership based on sender_id
        let isSentByCurrentUser = (senderID == currentUserID)
        
        print("🔍 PARSING MESSAGE DEBUG:")
        print("   ID: \(idString.prefix(8))")
        print("   realText: '\(realText ?? "nil")'")
        print("   senderID: '\(senderID ?? "nil")'")
        print("   currentUserID: '\(currentUserID)'")
        print("   isSentByCurrentUser: \(isSentByCurrentUser)")
        print("   recipientEmail: '\(recipientEmail ?? "nil")'")
        print("   senderEmail: '\(senderEmail ?? "nil")'")
        print("---")
        
        // Create Message with all fields including image data
        let message = Message(
            id: uuid,
            realText: realText,
            coverText: coverText,
            isSentByCurrentUser: isSentByCurrentUser,
            timestamp: timestamp,
            imageData: imageData,
            bitCount: bitCount,
            deliveryPath: deliveryPath,
            isAutoReply: isAutoReply,
            senderID: senderID
        )
        
        return message
    }
    
    private static func normalizeDeliveryPath(_ path: String) -> String {
        switch path.lowercased() {
            case "send_email": return "email"
            case "send_sms": return "sms"
            default: return path.lowercased()
        }
    }
}
