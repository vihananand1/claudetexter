// UPDATED APIStorageManager.swift - Include sender email information

import Foundation

/// Codable struct representing the payload sent to the backend for message storage.
struct StoreMessageRequest: Codable {
    let id: String
    let chat_id: String
    let real_text: String?
    let cover_text: String?
    let bitCount: Int?
    let isAutoReply: Bool
    let delivery_path: String   
    let timestamp: String
    let sender_id: String?
    let recipient_email: String?
    let to_email: String?
    let sender_email: String?  // NEW: Track sender email
    let from_email: String?    // NEW: Alternative field name
}

/// Singleton for sending messages to the backend API for persistent storage.
class APIStorageManager {
    static let shared = APIStorageManager()
    
    private let backendURL = "\(API.baseURL)/store_message"
    
    /// UPDATED: Store message with sender email information for better conversation tracking
    func storeMessage(
        id: UUID,
        senderID: String? = nil,
        chatID: UUID,
        realText: String?,
        coverText: String?,
        bitCount: Int?,
        isAutoReply: Bool,
        deliveryPath: String,
        timestamp: Date,
        recipientEmail: String? = nil,
        senderEmail: String? = nil  // NEW: Sender email parameter
    ) {
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: timestamp)
        
        print("📤 Sending to /store_message:")
        print("   realText: \(realText ?? "nil")")
        print("   coverText: \(coverText ?? "nil")")
        print("   chatID: \(chatID)")
        print("   deliveryPath: \(deliveryPath)")
        print("   timestamp: \(timestampStr)")
        print("   recipientEmail: \(recipientEmail ?? "nil")")
        print("   senderEmail: \(senderEmail ?? "nil")")  // NEW
        
        let payload = StoreMessageRequest(
            id: id.uuidString,
            chat_id: chatID.uuidString,
            real_text: realText,
            cover_text: coverText,
            bitCount: bitCount,
            isAutoReply: isAutoReply,
            delivery_path: deliveryPath,
            timestamp: timestampStr,
            sender_id: senderID,
            recipient_email: recipientEmail,
            to_email: recipientEmail,
            sender_email: senderEmail,  // NEW
            from_email: senderEmail     // NEW
        )
        
        if let jsonData = try? JSONEncoder().encode(payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📦 JSON payload:")
            print(jsonString)
        }
        
        guard let url = URL(string: backendURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data, let raw = String(data: data, encoding: .utf8) {
                print("📬 Response: \(raw)")
            }
            if let error = error {
                print("❌ Error: \(error.localizedDescription)")
            } else {
                print("✅ Message stored successfully")
            }
        }.resume()
    }
}

extension APIStorageManager {
    func storeMessageWithImage(
        id: UUID,
        senderID: String?,
        chatID: UUID,
        realText: String?,
        coverText: String?,
        bitCount: Int?,
        isAutoReply: Bool,
        deliveryPath: String,
        timestamp: Date,
        imageData: Data?,
        recipientEmail: String? = nil,
        senderEmail: String? = nil  // NEW: Sender email parameter
    ) {
        guard let url = URL(string: "\(API.baseURL)/store_message") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "id": id.uuidString,
            "sender_id": senderID ?? "",
            "chat_id": chatID.uuidString,
            "real_text": realText ?? "",
            "cover_text": coverText ?? "",
            "bit_count": bitCount ?? 0,
            "is_auto_reply": isAutoReply,
            "delivery_path": deliveryPath,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "recipient_email": recipientEmail ?? "",
            "to_email": recipientEmail ?? "",
            "sender_email": senderEmail ?? "",     // NEW
            "from_email": senderEmail ?? ""        // NEW
        ]
        
        // Include image data if present
        if let imageData = imageData {
            let imageBase64 = imageData.base64EncodedString()
            payload["image_data"] = imageBase64
            print("💾 Storing message with image data (\(imageData.count) bytes)")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Failed to store message: \(error)")
            } else {
                print("✅ Message stored successfully")
            }
        }.resume()
    }
}
