import Foundation
import GoogleSignIn
import SwiftUI

/// Provides static functions to send Email via backend API endpoints.
/// FIXED VERSION - Focuses on email only, includes proper recipient info
struct DeliveryManager {

    /// FIXED: Sends an email using the backend API with recipient info for proper storage
    // UPDATE the sendEmail function in DeliveryManager.swift to include sender email

    static func sendEmail(
        to: String,
        subject: String = "WindTexter",
        message: String,
        senderID: String? = nil,
        chatID: UUID? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(API.baseURL)/send_email") else {
            completion(false)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // CRITICAL: Get current user's email for sender identification
        let currentUserEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email
        
        // CRITICAL: Include sender email in the request
        var body: [String: Any] = [
            "to": to,
            "subject": subject,
            "message": message,
            "delivery_path": "send_email"
        ]
        
        // Add sender information for proper message routing
        if let senderID = senderID {
            body["sender_id"] = senderID
        }
        if let chatID = chatID {
            body["chat_id"] = chatID.uuidString
        }
        if let currentUserEmail = currentUserEmail {
            body["sender_email"] = currentUserEmail  // This is the key addition!
        }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("📧 Sending email with complete routing info:")
        print("   to: \(to)")
        print("   sender_id: \(senderID ?? "nil")")
        print("   chat_id: \(chatID?.uuidString ?? "nil")")
        print("   sender_email: \(currentUserEmail ?? "nil")")  // Debug log

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["status"] as? String == "sent" {
                print("✅ Email sent successfully with headers")
                completion(true)
            } else {
                print("❌ Email send error:", error?.localizedDescription ?? "Unknown")
                completion(false)
            }
        }.resume()
    }
}

extension DeliveryManager {
    /// FIXED: Sends an email with image attachment using the backend API
    static func sendEmailWithImage(
        to email: String,
        message: String,
        imageData: Data?,
        senderID: String? = nil,
        chatID: UUID? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(API.baseURL)/send_email_with_image") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload: [String: Any] = [
            "to": email,
            "message": message,
            "subject": "WindTexter"
        ]
        
        // Add sender and chat info if available
        if let senderID = senderID {
            payload["sender_id"] = senderID
        }
        if let chatID = chatID {
            payload["chat_id"] = chatID.uuidString
        }
        
        // Add image data as base64 if present
        if let imageData = imageData {
            let imageBase64 = imageData.base64EncodedString()
            payload["image_data"] = imageBase64
            payload["image_filename"] = "image.jpg"
            print("📧 Sending email with image (\(imageData.count) bytes)")
            print("   to: \(email)")
            print("   sender_id: \(senderID ?? "nil")")
            print("   chat_id: \(chatID?.uuidString ?? "nil")")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Failed to send email: \(error.localizedDescription)")
                    completion(false)
                } else if let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 {
                    print("Email with image sent successfully")
                    completion(true)
                } else {
                    print("Email sending failed with status code")
                    completion(false)
                }
            }
        }.resume()
    }
}
