// ChatView.Swift - COMPLETE FIXED VERSION WITH CHRONOLOGICAL ORDER BUG FIX AND TIMER CRASH PROTECTION

import SwiftUI
import CoreLocation
import Contacts
import GoogleSignIn
import GoogleSignInSwift

// Add this helper class for consistent device ID
class DeviceIDManager {
    static let shared = DeviceIDManager()
    private let deviceIDKey = "WindTexterDeviceID"
    
    private init() {}
    
    var deviceID: String {
        if let existingID = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existingID
        } else {
            // Create a new persistent device ID
            let newID = UUID().uuidString
            UserDefaults.standard.set(newID, forKey: deviceIDKey)
            return newID
        }
    }
}

struct OffsetOpacityModifier: ViewModifier {
    let xOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: xOffset)
            .opacity(opacity)
    }
}

struct IMessageSendTransition: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.85)
            .opacity(isVisible ? 1 : 0)
            .offset(x: isVisible ? 0 : 20, y: isVisible ? 0 : -8)
            .animation(.interpolatingSpring(stiffness: 220, damping: 22), value: isVisible)
    }
}

class ChatMessagesStore: ObservableObject {
    @Published var loadedMessageIDs: [UUID: Set<UUID>] = [:]
    @Published var messagesPerChat: [UUID: [Message]] = [:]
    @Published var latestChange = UUID()
    
    // NEW: Track message signatures to prevent cross-format duplicates
    private var messageSignatures: [UUID: Set<String>] = [:]
    
    func isDuplicate(_ newMessage: Message, in chat: Chat) -> Bool {
        let existingMessages = messagesPerChat[chat.id] ?? []
        let existingSignatures = messageSignatures[chat.id] ?? Set<String>()

        // Check by ID first
        if existingMessages.contains(where: { $0.id == newMessage.id }) {
            print("🔄 Duplicate detected by ID: \(newMessage.id.uuidString.prefix(8))")
            return true
        }
        
        // CRITICAL: Check by content signature
        let newSignature = newMessage.createContentSignature()
        if existingSignatures.contains(newSignature) {
            print("🔄 Duplicate detected by signature: \(newSignature)")
            return true
        }
        
        // Additional legacy checks for backward compatibility
        return existingMessages.contains(where: { existing in
            // Same content + timestamp + sender
            let sameContent = existing.realText == newMessage.realText &&
                             existing.coverText == newMessage.coverText
            let sameTimestamp = existing.timestamp == newMessage.timestamp
            let sameSender = existing.isSentByCurrentUser == newMessage.isSentByCurrentUser
            
            if sameContent && sameTimestamp && sameSender {
                print("🔄 Duplicate detected by legacy content check")
                return true
            }
            
            // Cross-format duplicate detection
            return Message.areContentEqual(existing, newMessage)
        })
    }

    // CRITICAL FIX: Synchronous loading with proper ordering
    func load(for chat: Chat) {
        print("📂 ChatMessagesStore.load() called for chat: \(chat.name)")
        
        let key = "savedMessages-\(chat.id.uuidString)"
        
        // CRITICAL FIX: Always reload from UserDefaults synchronously
        var loadedMessages: [Message] = []
        
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            
            print("📂 Found \(decoded.count) messages in UserDefaults for \(chat.name)")
            
            // Remove duplicates when loading from UserDefaults
            let uniqueMessages = removeDuplicates(from: decoded)
            
            // Set isSentByCurrentUser based on consistent device ID
            let currentDeviceID = DeviceIDManager.shared.deviceID
            for message in uniqueMessages {
                if let senderID = message.senderID {
                    message.isSentByCurrentUser = (senderID == currentDeviceID)
                }
            }
            
            loadedMessages = uniqueMessages
        } else {
            print("📂 No messages found in UserDefaults for \(chat.name)")
        }
        
        // CRITICAL FIX: Sort messages by timestamp BEFORE setting them
        let sortedMessages = loadedMessages.sorted { message1, message2 in
            let timestamp1 = parseTimestamp(message1.timestamp)
            let timestamp2 = parseTimestamp(message2.timestamp)
            return timestamp1 < timestamp2  // Oldest first for chronological order
        }
        
        print("📂 Sorted \(sortedMessages.count) messages chronologically")
        
        // CRITICAL FIX: Set all data synchronously to prevent race conditions
        messagesPerChat[chat.id] = sortedMessages
        loadedMessageIDs[chat.id] = Set(sortedMessages.map { $0.id })
        messageSignatures[chat.id] = Set(sortedMessages.map { $0.createContentSignature() })
        
        // Trigger UI update AFTER everything is set
        latestChange = UUID()
        
        print("✅ ChatMessagesStore loaded \(sortedMessages.count) messages for \(chat.name) in chronological order")
        
        // Save back the deduplicated and sorted messages
        if let encoded = try? JSONEncoder().encode(sortedMessages) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    // CRITICAL NEW FUNCTION: Force reload capability with proper ordering
    func forceReload(for chat: Chat) {
        print("🔄 ChatMessagesStore.forceReload() for chat: \(chat.name)")
        
        let key = "savedMessages-\(chat.id.uuidString)"
        
        // Always read fresh from UserDefaults
        var reloadedMessages: [Message] = []
        
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            
            print("📂 Force reloaded \(decoded.count) messages from UserDefaults for \(chat.name)")
            
            // Remove duplicates
            let uniqueMessages = removeDuplicates(from: decoded)
            
            // Set ownership based on device ID
            let currentDeviceID = DeviceIDManager.shared.deviceID
            for message in uniqueMessages {
                if let senderID = message.senderID {
                    message.isSentByCurrentUser = (senderID == currentDeviceID)
                }
            }
            
            reloadedMessages = uniqueMessages
        } else {
            print("📂 No messages found in UserDefaults for \(chat.name)")
        }
        
        // CRITICAL FIX: Sort messages chronologically BEFORE setting
        let sortedMessages = reloadedMessages.sorted { message1, message2 in
            let timestamp1 = parseTimestamp(message1.timestamp)
            let timestamp2 = parseTimestamp(message2.timestamp)
            return timestamp1 < timestamp2  // Oldest first
        }
        
        print("🔄 Force reload: Sorted \(sortedMessages.count) messages chronologically")
        
        // FORCE update - always replace existing data with sorted messages
        messagesPerChat[chat.id] = sortedMessages
        loadedMessageIDs[chat.id] = Set(sortedMessages.map { $0.id })
        messageSignatures[chat.id] = Set(sortedMessages.map { $0.createContentSignature() })
        
        // Force UI update
        latestChange = UUID()
        
        print("✅ Force reloaded \(sortedMessages.count) messages for \(chat.name) in chronological order")
    }

    func addMessage(_ message: Message, to chat: Chat) {
        // Use centralized duplicate detection
        guard !isDuplicate(message, in: chat) else {
            print("🔄 ChatMessagesStore: Skipping duplicate message")
            return
        }

        // Ensure senderID is set consistently
        if message.senderID == nil {
            message.senderID = DeviceIDManager.shared.deviceID
        }

        // CRITICAL FIX: Get current messages, add new one, then sort chronologically
        var updatedMessages = messagesPerChat[chat.id, default: []]
        updatedMessages.append(message)
        
        // CRITICAL FIX: Sort by timestamp after adding to maintain chronological order
        let sortedMessages = updatedMessages.sorted { message1, message2 in
            let timestamp1 = parseTimestamp(message1.timestamp)
            let timestamp2 = parseTimestamp(message2.timestamp)
            return timestamp1 < timestamp2  // Oldest first
        }
        
        // Set the sorted messages
        messagesPerChat[chat.id] = sortedMessages

        // Track ID and signature after successfully adding
        loadedMessageIDs[chat.id, default: []].insert(message.id)
        messageSignatures[chat.id, default: []].insert(message.createContentSignature())

        latestChange = UUID()
        save(chat: chat)

        print("✅ ChatMessagesStore: Added message and sorted chronologically. Total count: \(sortedMessages.count)")
    }

    // Enhanced function to remove duplicates with signature checking
    private func removeDuplicates(from messages: [Message]) -> [Message] {
        var uniqueMessages: [Message] = []
        var seenSignatures: Set<String> = []
        var seenIDs: Set<UUID> = []
        
        for message in messages {
            // Check by ID first
            if seenIDs.contains(message.id) {
                print("🗑️ Removing duplicate by ID: \(message.id.uuidString.prefix(8))")
                continue
            }
            
            // Check by signature
            let signature = message.createContentSignature()
            if seenSignatures.contains(signature) {
                print("🗑️ Removing duplicate by signature: \(signature)")
                continue
            }
            
            // Legacy duplicate check for additional safety
            let isDuplicate = uniqueMessages.contains { existing in
                let sameContent = existing.realText == message.realText &&
                                 existing.coverText == message.coverText
                let sameTimestamp = existing.timestamp == message.timestamp
                let sameSender = existing.isSentByCurrentUser == message.isSentByCurrentUser
                
                return sameContent && sameTimestamp && sameSender
            }
            
            if !isDuplicate {
                uniqueMessages.append(message)
                seenIDs.insert(message.id)
                seenSignatures.insert(signature)
            } else {
                print("🗑️ Removing duplicate by legacy check")
            }
        }
        
        return uniqueMessages
    }

    func save(chat: Chat) {
        if let liveMessages = messagesPerChat[chat.id],
           let encoded = try? JSONEncoder().encode(liveMessages) {
            UserDefaults.standard.set(encoded, forKey: "savedMessages-\(chat.id.uuidString)")
        }
    }
    
    // UTILITY: Clear all cached signatures (useful for debugging)
    func clearSignatureCache() {
        messageSignatures.removeAll()
        print("🧹 Cleared all message signature caches")
    }
    
    // UTILITY: Rebuild signature cache for a specific chat
    func rebuildSignatureCache(for chat: Chat) {
        if let messages = messagesPerChat[chat.id] {
            messageSignatures[chat.id] = Set(messages.map { $0.createContentSignature() })
            print("🔧 Rebuilt signature cache for \(chat.name): \(messageSignatures[chat.id]?.count ?? 0) signatures")
        }
    }
    
    // CRITICAL FIX: Helper function to parse timestamps consistently
    private func parseTimestamp(_ timestamp: String) -> Date {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: timestamp) {
            return date
        } else {
            isoFormatter.formatOptions = [.withInternetDateTime]
            return isoFormatter.date(from: timestamp) ?? Date()
        }
    }
}

// Add this helper function at the module level
func parseTimestamp(_ timestamp: String) -> Date {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    if let date = isoFormatter.date(from: timestamp) {
        return date
    } else {
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: timestamp) ?? Date()
    }
}

final class Message: Identifiable, Codable, ObservableObject, Equatable {
    var senderID: String? = nil
    var deliveryPath: String?
    let id: UUID
    var realText: String?
    var coverText: String?
    var isSentByCurrentUser: Bool
    let timestamp: String
    let imageData: Data?
    var bitCount: Int? = nil
    var isAutoReply: Bool = false
    var messageSource: String? = nil  // NEW: Track message source (backend, gmail, etc.)

    init(
        id: UUID = UUID(),
        realText: String?,
        coverText: String?,
        isSentByCurrentUser: Bool,
        timestamp: String,
        imageData: Data? = nil,
        bitCount: Int? = nil,
        deliveryPath: String? = nil,
        isAutoReply: Bool = false,
        senderID: String? = nil
    ) {
        print("🔍 MESSAGE INIT DEBUG:")
        print("   Received senderID parameter: '\(senderID ?? "NIL")'")
        
        self.id = id
        self.realText = realText
        self.coverText = coverText
        self.isSentByCurrentUser = isSentByCurrentUser
        self.timestamp = timestamp
        self.imageData = imageData
        self.bitCount = bitCount
        self.deliveryPath = deliveryPath
        self.isAutoReply = isAutoReply
        
        self.senderID = senderID ?? DeviceIDManager.shared.deviceID
        
        print("   Final self.senderID: '\(self.senderID ?? "NIL")'")
        print("---")
    }

    func displayText(showRealMessage: Bool) -> String {
        if showRealMessage {
            return realText ?? ""
        } else {
            return coverText ?? realText ?? ""
        }
    }
    
    static func ==(lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
               lhs.realText == rhs.realText &&
               lhs.coverText == rhs.coverText &&
               lhs.timestamp == rhs.timestamp
    }

    func formattedTimestamp() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            return displayFormatter.string(from: date)
        } else {
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: timestamp) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "h:mm a"
                return displayFormatter.string(from: date)
            }
            
            if timestamp.contains(":") && (timestamp.contains("AM") || timestamp.contains("PM") || timestamp.count <= 8) {
                return timestamp
            }
            
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            return displayFormatter.string(from: Date())
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, senderID, realText, coverText, isSentByCurrentUser, timestamp, imageData, deliveryPath, bitCount, isAutoReply, messageSource
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        deliveryPath = try container.decodeIfPresent(String.self, forKey: .deliveryPath)
        id = try container.decode(UUID.self, forKey: .id)
        realText = try container.decodeIfPresent(String.self, forKey: .realText)
        coverText = try container.decodeIfPresent(String.self, forKey: .coverText)
        senderID = try container.decodeIfPresent(String.self, forKey: .senderID)
        messageSource = try container.decodeIfPresent(String.self, forKey: .messageSource)
        
        timestamp = try container.decode(String.self, forKey: .timestamp)
        isSentByCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isSentByCurrentUser) ?? false
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        bitCount = try container.decodeIfPresent(Int.self, forKey: .bitCount)
        isAutoReply = try container.decodeIfPresent(Bool.self, forKey: .isAutoReply) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(realText, forKey: .realText)
        try container.encodeIfPresent(coverText, forKey: .coverText)
        try container.encode(isSentByCurrentUser, forKey: .isSentByCurrentUser)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(senderID, forKey: .senderID)
        try container.encodeIfPresent(deliveryPath, forKey: .deliveryPath)
        try container.encodeIfPresent(bitCount, forKey: .bitCount)
        try container.encode(isAutoReply, forKey: .isAutoReply)
        try container.encodeIfPresent(messageSource, forKey: .messageSource)
    }
    
    // CRITICAL: Enhanced content signature for better duplicate detection
    func createContentSignature() -> String {
        var components: [String] = []
        
        // Always include normalized timestamp
        let normalizedTimestamp = normalizeTimestamp(timestamp)
        components.append("timestamp:\(normalizedTimestamp)")
        
        // Include sender information
        components.append("sender:\(senderID ?? "unknown")")
        components.append("isSent:\(isSentByCurrentUser)")
        
        // CRITICAL: Normalize content for cross-format detection
        if let realText = realText?.trimmingCharacters(in: .whitespacesAndNewlines), !realText.isEmpty {
            components.append("real:\(realText)")
        }
        
        if let coverText = coverText?.trimmingCharacters(in: .whitespacesAndNewlines), !coverText.isEmpty {
            // If cover text is bitstream, mark it specially
            if coverText.allSatisfy({ $0 == "0" || $0 == "1" }) {
                components.append("bitstream:\(coverText)")
            } else {
                components.append("cover:\(coverText)")
            }
        }
        
        // Include image data size if present
        if let imageData = imageData {
            components.append("image:\(imageData.count)")
        }
        
        // Include delivery path
        components.append("path:\(deliveryPath ?? "unknown")")
        
        // Include message source if available
        if let source = messageSource {
            components.append("source:\(source)")
        }
        
        let combined = components.joined(separator: "|")
        return String(combined.hashValue)
    }
    
    // Helper to normalize timestamps for comparison
    private func normalizeTimestamp(_ timestamp: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: timestamp) {
            // Return as rounded to nearest second to handle minor timing differences
            let roundedDate = Date(timeIntervalSince1970: round(date.timeIntervalSince1970))
            return isoFormatter.string(from: roundedDate)
        } else {
            // Try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: timestamp) {
                return isoFormatter.string(from: date)
            }
            // Return original if can't parse
            return timestamp
        }
    }
    
    // ENHANCED: Better equality check that considers cross-format duplicates
    static func areContentEqual(_ lhs: Message, _ rhs: Message) -> Bool {
        // Quick check: same signature means definitely the same
        if lhs.createContentSignature() == rhs.createContentSignature() {
            return true
        }
        
        // Check if they have the same real content
        if let lhsReal = lhs.realText?.trimmingCharacters(in: .whitespacesAndNewlines),
           let rhsReal = rhs.realText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lhsReal.isEmpty && !rhsReal.isEmpty {
            if lhsReal == rhsReal {
                return true
            }
        }
        
        // Check timestamp proximity (within 5 seconds)
        let lhsTime = parseTimestamp(lhs.timestamp)
        let rhsTime = parseTimestamp(rhs.timestamp)
        let timeDifference = abs(lhsTime.timeIntervalSince(rhsTime))
        
        if timeDifference <= 5 {
            // Close timestamps, check for cross-format match
            
            // One has real text, other has bitstream
            if let lhsReal = lhs.realText, !lhsReal.isEmpty,
               let rhsCover = rhs.coverText, !rhsCover.isEmpty,
               rhsCover.allSatisfy({ $0 == "0" || $0 == "1" }) {
                return true // Likely the same message in different formats
            }
            
            // Reverse check
            if let rhsReal = rhs.realText, !rhsReal.isEmpty,
               let lhsCover = lhs.coverText, !lhsCover.isEmpty,
               lhsCover.allSatisfy({ $0 == "0" || $0 == "1" }) {
                return true // Likely the same message in different formats
            }
            
            // Same cover text
            if let lhsCover = lhs.coverText?.trimmingCharacters(in: .whitespacesAndNewlines),
               let rhsCover = rhs.coverText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !lhsCover.isEmpty && !rhsCover.isEmpty && lhsCover == rhsCover {
                return true
            }
        }
        
        return false
    }
}

struct ChatView: View {
    // CRITICAL FIX: Computed property that ensures messages are always in chronological order
    var scrollContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if messagesGroupedByPath.isEmpty {
                // Show a message when no messages match the selected path
                VStack {
                    Spacer()
                    if let selectedPath = selectedPathToReveal {
                        Text("No cover messages found for \(selectedPath.capitalized)")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .padding()
                    } else {
                        Text("")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                            .padding()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(messagesGroupedByPath.keys.sorted(), id: \.self) { path in
                    if let messages = messagesGroupedByPath[path] {
                        VStack(alignment: .leading, spacing: 8) {
                            // 🏷️ Path header label - only show if multiple paths AND we actually have multiple different paths with messages
                            if messagesGroupedByPath.keys.count > 1 && messagesGroupedByPath.keys.contains(where: { $0 != "email" && $0 != "" }) {
                                Text(path.uppercased())
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(10)
                                    .padding(.bottom, 5)
                            }

                            // 💬 CRITICAL FIX: Sort messages chronologically within each path
                            ForEach(sortedMessagesForPath(messages)) { message in
                                MessageBubble(message: message, showRealMessage: selectedPathToReveal == nil)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.7,
                                           alignment: message.isSentByCurrentUser ? .trailing : .leading)
                                    .padding(message.isSentByCurrentUser ? .leading : .trailing, 40)
                                    .frame(maxWidth: .infinity,
                                           alignment: message.isSentByCurrentUser ? .trailing : .leading)
                                    .id(message.id)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }
    
    // CRITICAL FIX: Helper function to sort messages chronologically
    private func sortedMessagesForPath(_ messages: [Message]) -> [Message] {
        return messages.sorted { message1, message2 in
            let timestamp1 = parseTimestamp(message1.timestamp)
            let timestamp2 = parseTimestamp(message2.timestamp)
            return timestamp1 < timestamp2  // Oldest first for chronological order
        }
    }

    var deliveryPaths: [String] {
        (try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData))?.sorted() ?? []
    }

    @Binding var chat: Chat
    
    // CRITICAL FIX: Ensure liveMessages are always sorted chronologically
    var liveMessages: [Message] {
        let messages = messageStore.messagesPerChat[chat.id] ?? []
        
        // CRITICAL FIX: Always sort by timestamp to maintain chronological order
        let sortedMessages = messages.sorted { message1, message2 in
            let timestamp1 = parseTimestamp(message1.timestamp)
            let timestamp2 = parseTimestamp(message2.timestamp)
            return timestamp1 < timestamp2  // Oldest first
        }
        
        print("📋 ChatView liveMessages count: \(sortedMessages.count) for chat \(chat.name) (sorted chronologically)")
        return sortedMessages
    }

    @EnvironmentObject var messageStore: ChatMessagesStore
    @State private var lastSentBitstream: [Int] = []
    @AppStorage("isSignedInToGmail") private var isSignedInToGmail: Bool = false
    @State private var emailPollingTimer: Timer?
    @State private var backendPollingTimer: Timer?
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var isUnlocked = false
    @State private var selectedPathToReveal: String? = nil
    @Binding var isInChat: Bool
    @Binding var chats: [Chat]
    @State private var lastSentMessageID: UUID?
    @AppStorage("selectedPathForChat") private var selectedPathForChatRaw: String = ""
    @State private var inputHeight: CGFloat = 40
    @State private var messageText: String = ""
    @State private var refreshToggle = false
    @State private var selectedImage: UIImage?
    @State private var showImagePicker: Bool = false
    @StateObject var locationManager = LocationManager()
    @State private var hasLoadedMessages = false
    
    // NEW: Contact management state
    @State private var showingContactDetail = false
    
    let deviceID = DeviceIDManager.shared.deviceID
    
    @AppStorage("selectedPaths") private var selectedPathsData: Data = Data()

    var selectedPaths: [String] {
        (try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData))?.sorted() ?? deliveryPaths
    }
    
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var allDeliveryPaths: [String] {
        Array(Set(liveMessages.compactMap { $0.deliveryPath })).sorted()
    }

    var messagesGroupedByPath: [String: [Message]] {
        let filteredMessages: [Message]
        
        if let selectedPath = selectedPathToReveal {
            // Only show messages from the selected path when in cover message mode
            filteredMessages = liveMessages.filter { message in
                let normalizedMessagePath = normalizeDeliveryPath(message.deliveryPath ?? "")
                let normalizedSelectedPath = normalizeDeliveryPath(selectedPath)
                return normalizedMessagePath == normalizedSelectedPath
            }
        } else {
            // Show all messages when in real message mode
            filteredMessages = liveMessages
        }
        
        let groups = Dictionary(grouping: filteredMessages, by: { $0.deliveryPath ?? "" })
        return groups.filter { !$0.value.isEmpty }
    }
    
    var body: some View {
        VStack {
            // Updated ChatView header section with name truncation
            // Replace the existing header ZStack in your ChatView body with this code

            ZStack {
                // Top-left toggle
                HStack {
                    Menu {
                        Button("Show All Real Messages", action: {
                            selectedPathToReveal = nil
                            saveSelectedPath(nil)
                        })
                        ForEach(getAvailablePathsForContact(chat), id: \.self) { path in
                            Button("Show Cover Messages from \(path)", action: {
                                selectedPathToReveal = path
                                saveSelectedPath(path)
                            })
                        }
                    } label: {
                        Label(
                            selectedPathToReveal.map { "(\($0))" } ?? "Real Text",
                            systemImage: selectedPathToReveal == nil ? "eye.slash.fill" : "eye.fill"
                        )
                        .foregroundColor(.blue)
                        .padding(10)
                    }

                    Spacer()
                }
                
                // Centered chat name - MADE CLICKABLE FOR CONTACT MANAGEMENT WITH TRUNCATION
                HStack {
                    Spacer()
                    
                    // Make this entire section clickable
                    Button(action: {
                        showingContactDetail = true
                    }) {
                        HStack(spacing: 6.7) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 45, height: 45)
                                .overlay(
                                    Text(String(chat.name.prefix(1)))
                                        .font(.title)
                                        .foregroundColor(.white)
                                )
                            
                            Text(chat.name)
                                .font(.title3)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1) // Ensure single line
                                .truncationMode(.tail) // Add ellipsis at the end
                        }
                    }
                    .buttonStyle(PlainButtonStyle()) // Removes default button styling
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.4) // Reduced from 0.5 to 0.4 to prevent overlap
                    
                    Spacer()
                }
                
                // Top-right star button - FIXED to update immediately
                HStack {
                    Spacer()
                    Button(action: {
                        toggleFavorite()
                    }) {
                        // CRITICAL FIX: Read favorite status from chats array, not local chat binding
                        let isFavorite = chats.first(where: { $0.id == chat.id })?.isFavorite ?? false
                        
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .resizable()
                            .frame(width: 26, height: 26)
                            .foregroundColor(isFavorite ? .yellow : .gray)
                            .padding()
                    }
                    // CRITICAL FIX: Animation based on the actual chats array value
                    .animation(.easeInOut(duration: 0.2), value: chats.first(where: { $0.id == chat.id })?.isFavorite ?? false)
                }
            }
            .padding(.top, 6)

            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.2) : Color.gray.opacity(0.6))
                .padding(.horizontal, 10)
            
            ScrollViewReader { proxy in
                ScrollView {
                    scrollContent
                }
                .id(refreshToggle) // This forces refresh when refreshToggle changes
                .onAppear {
                    self.scrollProxy = proxy
                }
                .onTapGesture {
                    isTextFieldFocused = false
                }
                .onChange(of: lastSentMessageID) { newID in
                    guard let id = newID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                // CRITICAL FIX: Force refresh UI whenever messageStore updates
                .onReceive(messageStore.$latestChange) { _ in
                    DispatchQueue.main.async {
                        print("🎯 ChatView received messageStore update for chat \(self.chat.name)")
                        print("📊 Current message count: \(self.liveMessages.count)")
                        self.refreshToggle.toggle()
                        self.scrollToBottom(animated: false)
                    }
                }
            }
                
            VStack(spacing: 6) {
                if let image = selectedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .clipped()
                            .padding(.leading, 8)
                        
                        Spacer()
                        
                        Button(action: {
                            selectedImage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.system(size: 20))
                        }
                        .padding(.trailing, 10)
                    }
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
                    .padding(.horizontal, 10)
                }
                
                HStack(alignment: .bottom) {
                    ZStack(alignment: .leading) {
                        if messageText.isEmpty {
                            Text("Type a message...")
                                .foregroundColor(Color.gray)
                                .padding(.leading, 20)
                        }
                        
                        GrowingTextEditor(
                            text: $messageText,
                            dynamicHeight: $inputHeight,
                            minHeight: 40,
                            maxHeight: 120
                        )
                        .frame(height: inputHeight)
                        .frame(maxWidth: .infinity)
                        .padding(.leading, 10)
                        .focused($isTextFieldFocused)
                    }
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20))
                            .padding(8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        showImagePicker = true
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .padding(8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 10)
                }
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingContactDetail) {
            ContactDetailViewForChat(chat: chat, chats: $chats)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        
        // CRITICAL FIX: Multiple lifecycle hooks to ensure messages load
        .onAppear {
            print("🎯 ChatView.onAppear for chat: \(chat.name)")
            setupChatViewForMessages()
            isInChat = true
        }
        
        // CRITICAL FIX: Also trigger on NavigationLink activation
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            print("🎯 App entering foreground - refreshing chat")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.forceRefreshMessages()
            }
        }
        
        // CRITICAL FIX: Listen for view appearing after navigation
        .onChange(of: isInChat) { inChat in
            if inChat {
                print("🎯 isInChat became true - setting up messages")
                setupChatViewForMessages()
            }
        }

        .onDisappear {
            // CRITICAL FIX: Safely handle chat name access in case chat was deleted
            let chatName = chats.first(where: { $0.id == chat.id })?.name ?? "Unknown Chat"
            print("🎯 ChatView.onDisappear for chat: \(chatName)")
            
            isInChat = false
            
            // CRITICAL FIX: Immediate timer cleanup to prevent crashes
            cleanupTimers()
            
            // CRITICAL FIX: Only update preview if chat still exists
            if chats.contains(where: { $0.id == chat.id }) {
                updateChatPreviewToLatestMessage()
                markChatAsRead()
            } else {
                print("⚠️ Chat was deleted, skipping preview update and mark as read")
            }
        }
        .onChange(of: selectedPathToReveal != nil) { _ in
            refreshToggle.toggle()
        }
    }
    
    // CRITICAL FIX: Store chat ID to prevent index out of range errors
    private func setupChatViewForMessages() {
        print("🚀 setupChatViewForMessages() called for \(chat.name)")
        
        // CRITICAL FIX: Store chat ID early to prevent crashes if chat gets deleted
        let chatID = chat.id
        let chatName = chat.name
        
        // CRITICAL FIX: Stop any ongoing timers first to prevent interference
        cleanupTimers()
        
        // STEP 1: CRITICAL FIX - Load messages synchronously first, with protection against race conditions
        print("📂 Loading messages synchronously for immediate display...")
        messageStore.load(for: chat)
        
        let messageCount = liveMessages.count
        print("📊 Loaded \(messageCount) messages synchronously for \(chatName)")
        
        // STEP 2: Force UI refresh to show loaded messages immediately
        DispatchQueue.main.async {
            print("🎯 Forcing UI refresh with \(self.liveMessages.count) messages")
            self.refreshToggle.toggle()
            
            // Scroll to bottom if we have messages
            if !self.liveMessages.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.scrollToBottom(animated: false)
                }
            }
        }
        
        // STEP 3: Mark chat as read
        markChatAsRead()
        
        // STEP 4: Set up polling only once, with delay to avoid interfering with initial load
        if !hasLoadedMessages {
            hasLoadedMessages = true
            print("🔧 Setting up polling for first time (with delay)")
            
            // CRITICAL FIX: Clean up duplicates AFTER initial load is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Check if chat still exists before cleanup
                if self.chats.contains(where: { $0.id == chatID }) {
                    self.cleanupDuplicateMessages(for: self.chat)
                }
            }
            
            if let restoredPath = try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())[chatID] {
                selectedPathToReveal = restoredPath
            }
            
            // Get current user's email for conversation polling
            guard let currentUserEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email,
                  let chatPartnerEmail = chat.email else {
                print("❌ Missing email information for conversation polling")
                return
            }
            
            // CRITICAL FIX: Delay initial backend fetch to avoid race condition with UI load
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // CRITICAL FIX: Check if chat still exists before setting up polling
                guard self.chats.contains(where: { $0.id == chatID }) else {
                    print("⚠️ Chat no longer exists, skipping polling setup")
                    return
                }
                
                print("📡 Starting delayed backend polling setup...")
                
                // Initial conversation fetch (asynchronous, won't affect immediate display)
                BackendAPI.fetchConversationMessages(
                    for: "send_email",
                    currentUserEmail: currentUserEmail,
                    chatPartnerEmail: chatPartnerEmail,
                    chatID: chatID // Use stored ID
                ) { backendMessages in
                    DispatchQueue.main.async {
                        // CRITICAL FIX: Check if chat still exists before processing messages
                        guard let currentChat = self.chats.first(where: { $0.id == chatID }) else {
                            print("⚠️ Chat deleted during initial fetch, skipping message processing")
                            return
                        }
                        
                        print("📥 Initial delayed fetch: Got \(backendMessages.count) messages from backend")
                        
                        // CRITICAL FIX: Only add truly new messages to prevent overwriting loaded messages
                        let existingCount = self.liveMessages.count
                        print("📊 Current message count before backend merge: \(existingCount)")
                        
                        var addedCount = 0
                        for message in backendMessages {
                            message.messageSource = "backend"
                            if !self.messageStore.isDuplicate(message, in: currentChat) {
                                self.addMessageIfNew(message, to: currentChat)
                                addedCount += 1
                            }
                        }
                        
                        print("📊 Added \(addedCount) new messages from backend. Total now: \(self.liveMessages.count)")
                    }
                }

                // Start polling timer with further delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    // CRITICAL FIX: Store reference to avoid retain cycles
                    self.backendPollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                        // CRITICAL FIX: Check if chat still exists before polling
                        guard let currentChat = self.chats.first(where: { $0.id == chatID }) else {
                            print("⚠️ Chat deleted during polling, stopping timer")
                            self.backendPollingTimer?.invalidate()
                            self.backendPollingTimer = nil
                            return
                        }
                        
                        BackendAPI.fetchConversationMessages(
                            for: "send_email",
                            currentUserEmail: currentUserEmail,
                            chatPartnerEmail: chatPartnerEmail,
                            chatID: chatID // Use stored ID
                        ) { backendMessages in
                            DispatchQueue.main.async {
                                // Double-check chat still exists
                                guard let currentChat = self.chats.first(where: { $0.id == chatID }) else {
                                    print("⚠️ Chat deleted during polling callback, stopping timer")
                                    self.backendPollingTimer?.invalidate()
                                    self.backendPollingTimer = nil
                                    return
                                }
                                
                                var hasNewMessages = false
                                for message in backendMessages {
                                    message.messageSource = "backend"
                                    if !self.messageStore.isDuplicate(message, in: currentChat) {
                                        self.addMessageIfNew(message, to: currentChat)
                                        hasNewMessages = true
                                    }
                                }
                                
                                if hasNewMessages {
                                    print("📊 Polling added new messages. Total now: \(self.liveMessages.count)")
                                }
                            }
                        }
                    }
                }
                
                // Gmail polling with delay
                if self.isSignedInToGmail {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        // CRITICAL FIX: Check if chat still exists before setting up Gmail polling
                        guard self.chats.contains(where: { $0.id == chatID }) else {
                            print("⚠️ Chat deleted, skipping Gmail polling setup")
                            return
                        }
                        
                        self.fetchIncomingEmailsFromGmail()
                        self.emailPollingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
                            // Check if chat still exists before Gmail polling
                            guard self.chats.contains(where: { $0.id == chatID }) else {
                                print("⚠️ Chat deleted during Gmail polling, stopping timer")
                                self.emailPollingTimer?.invalidate()
                                self.emailPollingTimer = nil
                                return
                            }
                            
                            self.fetchIncomingEmailsFromGmail()
                        }
                    }
                }
            }
        } else {
            print("🔧 Polling already set up, just refreshing messages")
            // Even if polling is set up, ensure we have the latest messages displayed
            DispatchQueue.main.async {
                self.refreshToggle.toggle()
            }
        }
    }

    // CRITICAL FIX: Force refresh messages and UI with better protection
    private func forceRefreshMessages() {
        print("🔄 forceRefreshMessages() called for \(chat.name)")
        
        // CRITICAL FIX: Don't use forceReload as it might clear messages, use regular load instead
        messageStore.load(for: chat)
        
        // Force UI refresh immediately
        DispatchQueue.main.async {
            let messageCount = self.liveMessages.count
            print("📊 After refresh: \(messageCount) messages for \(self.chat.name)")
            
            // Only trigger UI update if we actually have messages
            if messageCount > 0 {
                self.refreshToggle.toggle()
                
                // Scroll to bottom with delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.scrollToBottom(animated: false)
                }
            } else {
                print("⚠️ No messages found during refresh - may need to investigate storage")
                // Still trigger refresh to show empty state
                self.refreshToggle.toggle()
            }
        }
    }

    // CRITICAL FIX: Enhanced cleanup with force stop
    private func cleanupTimers() {
        print("🧹 Cleaning up timers...")
        
        emailPollingTimer?.invalidate()
        emailPollingTimer = nil
        
        backendPollingTimer?.invalidate()
        backendPollingTimer = nil
        
        print("🧹 Timers cleaned up")
    }
    
    private func handleNewReceivedMessage(_ message: Message) {
        addMessageIfNew(message, to: chat)
        
        // Since user is actively in the chat, don't increment unread counter
        // The message is considered "read" immediately
        print("📨 Received new message in active chat - not incrementing unread count")
        
        scrollToBottom()
    }

    func addMessageIfNew(_ message: Message, to chat: Chat) {
        let currentDeviceID = DeviceIDManager.shared.deviceID
        
        if message.senderID != nil {
            message.isSentByCurrentUser = (message.senderID == currentDeviceID)
            print("  Message has senderID '\(message.senderID!)', isSentByCurrentUser: \(message.isSentByCurrentUser)")
        } else {
            print("⚠️ Message missing senderID - keeping as received message")
            message.isSentByCurrentUser = false
        }
        
        // CRITICAL FIX: Normalize the delivery path before storing
        message.deliveryPath = normalizeDeliveryPath(message.deliveryPath ?? "email")
        print("📍 Normalized delivery path: '\(message.deliveryPath ?? "nil")'")

        // Rest of your existing logic...
        let existing = messageStore.messagesPerChat[chat.id] ?? []
        let newSignature = message.createContentSignature()
        let existingSignatures = Set(existing.map { $0.createContentSignature() })

        print("🔍 DEBUG: Checking message for duplicates:")
        print("   New message ID: \(message.id.uuidString.prefix(8))")
        print("   New message signature: \(newSignature)")
        print("   New message realText: '\(message.realText ?? "nil")'")
        print("   New message coverText: '\(message.coverText ?? "nil")'")
        print("   Has image: \(message.imageData != nil)")
        if let imageData = message.imageData {
            print("   Image size: \(imageData.count) bytes")
        }

        if existingSignatures.contains(newSignature) {
            print("🔄 DUPLICATE DETECTED via signature. Message not added.")
            return
        }

        // CRITICAL FIX: addMessage now handles sorting automatically
        messageStore.addMessage(message, to: chat)
    }

    func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }

        // Convert image to data if present
        var imageData: Data? = nil
        if let image = selectedImage {
            imageData = image.jpegData(compressionQuality: 0.7)
            print("📸 Image converted to data: \(imageData?.count ?? 0) bytes")
        }

        DispatchQueue.main.async {
            messageText = ""
            selectedImage = nil
        }

        let currentDeviceID = DeviceIDManager.shared.deviceID

        // FOCUS ONLY ON EMAIL
        guard let recipientEmail = chat.email else {
            print("❌ No email address for this chat")
            return
        }
        
        // CRITICAL: Get current user's email for proper conversation tracking
        guard let currentUserEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email else {
            print("❌ No current user email available")
            return
        }
        
        print("💥 SENDING MESSAGE:")
        print("   from: \(currentUserEmail)")
        print("   to: \(recipientEmail)")
        print("   device_id: \(currentDeviceID)")
        print("   chat_id: \(chat.id)")

        // Handle image messages - send directly without bitstream processing
        if let imageData = imageData {
            let timestamp = ISO8601DateFormatter().string(from: Date())

            let msg = Message(
                realText: trimmed.isEmpty ? nil : trimmed,
                coverText: trimmed.isEmpty ? nil : trimmed,
                isSentByCurrentUser: true,
                timestamp: timestamp,
                imageData: imageData
            )

            msg.senderID = currentDeviceID
            msg.deliveryPath = "email"
            msg.messageSource = "sent" // Mark as sent message

            // CRITICAL FIX: addMessage now handles chronological sorting automatically
            messageStore.addMessage(msg, to: chat)
            lastSentMessageID = msg.id
            scrollToBottom()

            // Send via email
            DeliveryManager.sendEmailWithImage(
                to: recipientEmail,
                message: trimmed.isEmpty ? "📸 Image" : trimmed,
                imageData: imageData,
                senderID: currentDeviceID,
                chatID: chat.id
            ) { success in
                print(success ? "✅ Email with image sent" : "❌ Email failed")
            }

            // CRITICAL: Store message in backend with complete routing information
            if let timestampDate = ISO8601DateFormatter().date(from: timestamp) {
                APIStorageManager.shared.storeMessageWithImage(
                    id: msg.id,
                    senderID: msg.senderID,
                    chatID: chat.id,
                    realText: trimmed.isEmpty ? nil : trimmed,
                    coverText: trimmed.isEmpty ? nil : trimmed,
                    bitCount: nil,
                    isAutoReply: false,
                    deliveryPath: "email",
                    timestamp: timestampDate,
                    imageData: imageData,
                    recipientEmail: recipientEmail,
                    senderEmail: currentUserEmail
                )
            }

            return
        }

        // Text message processing with complete routing
        generateBitstream(for: trimmed) { bits, bitCount in
            DispatchQueue.main.async {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let bitstream = bits.map { String($0) }.joined()

                print("💥 Processing text message:")
                print("   realText: '\(trimmed)'")
                print("   bitstream length: \(bitstream.count)")
                print("   timestamp: \(timestamp)")

                let msg = Message(
                    realText: trimmed,
                    coverText: bitstream,
                    isSentByCurrentUser: true,
                    timestamp: timestamp,
                    imageData: nil
                )

                msg.senderID = currentDeviceID
                msg.deliveryPath = "email"
                msg.bitCount = bitCount
                msg.messageSource = "sent" // Mark as sent message

                // CRITICAL FIX: addMessage now handles chronological sorting automatically
                messageStore.addMessage(msg, to: chat)
                lastSentMessageID = msg.id
                scrollToBottom()

                // Send via email WITH proper headers
                DeliveryManager.sendEmail(
                    to: recipientEmail,
                    message: bitstream,
                    senderID: currentDeviceID,
                    chatID: chat.id
                ) { success in
                    print(success ? "✅ Email sent to \(recipientEmail)" : "❌ Email failed")
                    
                    if !success {
                        print("❌ Email sending failed - message may not be delivered")
                    }
                }

                // CRITICAL: Store in backend with COMPLETE routing information
                if let timestampDate = ISO8601DateFormatter().date(from: timestamp) {
                    print("💾 Storing message in backend:")
                    print("   sender_email: \(currentUserEmail)")
                    print("   recipient_email: \(recipientEmail)")
                    print("   sender_id: \(currentDeviceID)")
                    print("   chat_id: \(chat.id)")
                    
                    APIStorageManager.shared.storeMessage(
                        id: msg.id,
                        senderID: msg.senderID,
                        chatID: chat.id,
                        realText: trimmed,
                        coverText: bitstream,
                        bitCount: bitCount,
                        isAutoReply: false,
                        deliveryPath: "email",
                        timestamp: timestampDate,
                        recipientEmail: recipientEmail,
                        senderEmail: currentUserEmail
                    )
                } else {
                    print("❌ Failed to convert timestamp for backend storage")
                }
            }
        }
    }

    func fetchAutoReply(to userMessage: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/generate_reply") else {
            completion(nil)
            return
        }
        
        let history = liveMessages.suffix(10).map { $0.displayText(showRealMessage: selectedPathToReveal != nil) }
        let payload: [String: Any] = [
            "chat_history": history,
            "last_message": userMessage
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reply = json["reply"] as? String {
                completion(reply)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    func saveSelectedPath(_ path: String?) {
        var allSelections = (try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())) ?? [:]
        allSelections[chat.id] = path
        if let data = try? JSONEncoder().encode(allSelections),
           let jsonString = String(data: data, encoding: .utf8) {
            selectedPathForChatRaw = jsonString
        }
    }
    
    private func updateChatTimeConsistently(with message: Message) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].time = message.formattedTimestamp()
        }
    }
        
    func updateChatPreviewToLatestMessage() {
        // CRITICAL FIX: Safely check if chat still exists before accessing it
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else {
            print("⚠️ updateChatPreviewToLatestMessage: Chat no longer exists in array")
            return
        }
        
        let chatName = chats[index].name
        print("🏃‍♂️ updateChatPreviewToLatestMessage called for \(chatName)")
        
        let allMessages = liveMessages
        let validMessages = allMessages.filter { message in
            let hasRealText = !(message.realText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasCoverText = !(message.coverText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasImage = message.imageData != nil
            
            return hasRealText || hasCoverText || hasImage
        }
        
        let sortedMessages = validMessages.sorted { $0.timestamp > $1.timestamp }
        
        guard let latestMessage = sortedMessages.first else {
            print("   No valid messages found for preview update")
            return
        }
        
        print("   Latest message has imageData: \(latestMessage.imageData != nil)")
        print("   Latest message realText: '\(latestMessage.realText ?? "nil")'")
        print("   Latest message timestamp: \(latestMessage.timestamp)")
        
        if latestMessage.imageData != nil {
            chats[index].realMessage = latestMessage.realText?.isEmpty == false ? latestMessage.realText! : "📸 Image"
            chats[index].coverMessage = "📸 Image"
            print("     Set preview to IMAGE on exit")
        } else if latestMessage.isSentByCurrentUser {
            chats[index].realMessage = latestMessage.realText ?? ""
            chats[index].coverMessage = latestMessage.coverText ?? ""
            print("     Set preview to SENT TEXT on exit")
        } else {
            if let realText = latestMessage.realText, !realText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chats[index].realMessage = realText
                chats[index].coverMessage = latestMessage.coverText ?? realText
                print("     Set preview to RECEIVED TEXT (decoded) on exit")
            } else {
                chats[index].realMessage = latestMessage.coverText ?? ""
                chats[index].coverMessage = latestMessage.coverText ?? ""
                print("     Set preview to RECEIVED TEXT (bitstream only) on exit")
            }
        }
        
        chats[index].time = latestMessage.formattedTimestamp()
        
        print("   Final on exit - realMessage: '\(chats[index].realMessage)'")
        print("   Final on exit - coverMessage: '\(chats[index].coverMessage.prefix(30))...'")
    }
    
    func scheduleAutoReply() {
        let delay = Double.random(in: 1.5...3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let replies = [
                "Okay", "Sure", "Let me know.", "Interesting...", "Sounds good.",
                "I'll check.", "Alright.", "Got it.", "Thanks!", "Cool."
            ]
            let reply = replies.randomElement() ?? "Okay"
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestampString = isoFormatter.string(from: Date())
            
            let message = Message(
                realText: nil,
                coverText: reply,
                isSentByCurrentUser: false,
                timestamp: timestampString,
                imageData: nil
            )
            
            message.messageSource = "auto_reply"
            
            withAnimation(.easeOut(duration: 0.35)) {
                messageStore.addMessage(message, to: chat)
                lastSentMessageID = message.id
            }
            
            scrollToBottom()
        }
    }
    
    func normalizeDeliveryPath(_ path: String) -> String {
        let pathLower = path.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let pathMap: [String: String] = [
            "send_email": "email",
            "send_sms": "sms",
        ]
        
        return pathMap[pathLower] ?? pathLower
    }
    
    func scrollToBottom(animated: Bool = true) {
        guard let proxy = scrollProxy, let last = liveMessages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated {
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    func getAvailablePathsForContact(_ chat: Chat) -> [String] {
        let key = "availablePaths-\(chat.phoneNumber ?? chat.email ?? "unknown")"
        let raw = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []

        // CRITICAL FIX: Don't filter out anything if we don't know the actual paths
        // Let the contact detail view handle checking with the server
        print("📋 Cached paths for \(chat.name): \(raw)")
        
        if raw.isEmpty {
            print("⚠️ No cached paths for \(chat.name) - contact may have sharing disabled")
            return [] // Return empty instead of assuming ["Email"]
        }
        
        return raw.filter { $0.lowercased() != "windtexter" }
    }

    func fetchIncomingEmailsFromGmail() {
        let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString ??
                    UserDefaults.standard.string(forKey: "gmailAccessToken")

        guard let accessToken = token else {
            return
        }

        GmailService.fetchEmailIDs(accessToken: accessToken) { ids in
            for id in ids {
                GmailService.fetchEmailBody(id: id, token: accessToken) { body, timestampString, sender, recipient, customHeaders in
                    guard let decodedBody = body else { return }
                    
                    print("📧 Processed email with headers: \(customHeaders ?? [:])")
                    
                    if let chatID = customHeaders?["chatID"],
                       let chatUUID = UUID(uuidString: chatID) {
                        print("📧 Email belongs to chat: \(chatID)")
                    }
                }
            }
        }
    }
    
    func normalize(_ string: String?) -> String {
        guard let string = string else { return "" }
        return string.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
        
    func toggleFavorite() {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                chats[index].isFavorite.toggle()
            }
            print("⭐ Toggled favorite for \(chat.name): \(chats[index].isFavorite)")
        }
    }
        
    func generateBitstream(for message: String, completion: @escaping ([Int], Int) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/split_cover_chunks") else {
            completion([], 0)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "message": message,
            "path": "send_email"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion([], 0)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let bitStrings = json["bitstream"] as? [String],
                  let count = json["bit_count"] as? Int else {
                completion([], 0)
                return
            }

            let bits = bitStrings.compactMap { Int($0) }
            completion(bits, count)
        }.resume()
    }

    // CRITICAL FIX: Better duplicate cleanup that doesn't interfere with loaded messages
    func cleanupDuplicateMessages(for chat: Chat) {
        print("🧹 cleanupDuplicateMessages() called for \(chat.name)")
        
        let key = "savedMessages-\(chat.id.uuidString)"
        
        guard let data = UserDefaults.standard.data(forKey: key),
              let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            print("🧹 No messages to clean up for \(chat.name)")
            return
        }
        
        print("🧹 Cleaning up \(messages.count) messages for \(chat.name)")
        
        // Sort by timestamp to keep the earliest version of duplicates
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        var uniqueMessages: [Message] = []
        var seenSignatures: Set<String> = []
        
        for message in sortedMessages {
            let signature = message.createContentSignature()
            
            if seenSignatures.contains(signature) {
                print("🗑️ Removing duplicate by signature: \(signature)")
                continue
            }
            
            let isDuplicate = uniqueMessages.contains { existing in
                if existing.id == message.id {
                    print("🗑️ Removing duplicate by ID: \(message.id.uuidString.prefix(8))")
                    return true
                }
                
                let sameContent = existing.realText == message.realText &&
                                 existing.coverText == message.coverText
                let sameTimestamp = existing.timestamp == message.timestamp
                let sameSender = existing.isSentByCurrentUser == message.isSentByCurrentUser
                
                if sameContent && sameTimestamp && sameSender {
                    print("🗑️ Removing content duplicate:")
                    print("   Keeping: ID=\(existing.id.uuidString.prefix(8)), content=\(existing.displayText(showRealMessage: false).prefix(20))...")
                    print("   Removing: ID=\(message.id.uuidString.prefix(8)), content=\(message.displayText(showRealMessage: false).prefix(20))...")
                    return true
                }
                
                return false
            }
            
            if !isDuplicate {
                uniqueMessages.append(message)
                seenSignatures.insert(signature)
            } else {
                print("🗑️ Removing duplicate by legacy check")
            }
        }
        
        print("🧹 Cleaned up: \(messages.count) -> \(uniqueMessages.count) messages")
        
        // CRITICAL FIX: Only save back to UserDefaults, don't clear messageStore
        if let encoded = try? JSONEncoder().encode(uniqueMessages) {
            UserDefaults.standard.set(encoded, forKey: key)
            print("  Saved cleaned messages to UserDefaults")
        }
        
        // CRITICAL FIX: Don't reset messageStore here as it might clear currently loaded messages
        // messageStore.messagesPerChat[chat.id] = []  // REMOVED THIS LINE
        print("🧹 Cleanup complete - messageStore left intact")
    }
    
    func decodeBitstream(bits: [Int], completion: @escaping (String?) -> Void) {
        
        guard let url = URL(string: "\(API.baseURL)/decode_cover_chunks") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "bit_sequence": bits,
            "compression_method": "utf8"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let decoded = json["decoded_text"] as? String
            else {
                print("❌ Failed to decode bitstream: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }

            completion(decoded)
        }.resume()
    }
        
    func updateChatContent(realText: String?, coverText: String?, imageData: Data? = nil) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = isoFormatter.string(from: Date())
            
            let tempMessage = Message(
                realText: realText,
                coverText: coverText,
                isSentByCurrentUser: true,
                timestamp: timestamp,
                imageData: imageData
            )
            
            if imageData != nil {
                chats[index].realMessage = realText?.isEmpty == false ? realText! : "📸 Image"
                chats[index].coverMessage = "📸 Image"
            } else {
                let fallback = "New message"
                
                if let realText = realText, !realText.isEmpty {
                    chats[index].realMessage = realText
                } else {
                    chats[index].realMessage = fallback
                }
                
                if let coverText = coverText, !coverText.isEmpty {
                    chats[index].coverMessage = coverText
                } else {
                    chats[index].coverMessage = fallback
                }
            }
            
            chats[index].time = tempMessage.formattedTimestamp()
        }
    }
        
    func loadMessages() {
        print("🔄 ChatView.loadMessages() called for chat: \(chat.name)")
        
        // Always load from messageStore (which will sort chronologically)
        messageStore.load(for: chat)
        
        // Force UI refresh
        DispatchQueue.main.async {
            let messageCount = self.messageStore.messagesPerChat[self.chat.id]?.count ?? 0
            print("📊 Loaded \(messageCount) messages for \(self.chat.name)")
            
            // Force refresh the UI
            self.refreshToggle.toggle()
            
            // Scroll to bottom if we have messages
            if messageCount > 0 {
                self.scrollToBottom(animated: false)
            }
        }
    }
    
    func markChatAsRead() {
        // CRITICAL FIX: Safely check if chat still exists before accessing it
        guard let index = chats.firstIndex(where: { $0.id == chat.id }) else {
            print("⚠️ markChatAsRead: Chat no longer exists in array")
            return
        }
        
        let previousCount = chats[index].unreadCount
        chats[index].unreadCount = 0
        print("  ChatView: Marked chat '\(chats[index].name)' as read (was: \(previousCount), now: 0)")
    }
}

// MARK: - Contact Management Integration for ChatView

// Updated ContactDetailViewForChat with simplified auto-sharing

struct ContactDetailViewForChat: View {
    let chat: Chat
    @Binding var chats: [Chat]
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var serverPaths: [String] = [] // Server-reported paths
    @State private var isLoadingServerPaths = false
    @State private var lastServerCheck: Date?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var messageStore: ChatMessagesStore
    
    // Get current chat data from chats array
    private var currentChat: Chat {
        return chats.first(where: { $0.id == chat.id }) ?? chat
    }
    
    // Convert Chat to Contact for the management system
    private var contact: Contact {
        Contact(
            name: currentChat.name,
            phoneNumber: currentChat.phoneNumber,
            email: currentChat.email
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(String(currentChat.name.prefix(1).uppercased()))
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
                        Text(currentChat.name)
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .padding(.top)
                    
                    // Contact Information
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Contact Information")
                        
                        VStack(spacing: 12) {
                            if let email = currentChat.email {
                                ContactInfoRow(
                                    icon: "envelope.fill",
                                    title: "Email",
                                    value: email,
                                    color: .blue
                                )
                            }
                            
                            if let phone = currentChat.phoneNumber {
                                ContactInfoRow(
                                    icon: "phone.fill",
                                    title: "Phone",
                                    value: phone,
                                    color: .green
                                )
                            }
                            
                            if currentChat.email == nil && currentChat.phoneNumber == nil {
                                VStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    
                                    Text("No contact information available")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Add phone or email to enable more delivery paths")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    // Available Delivery Paths Section (Auto-shared)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SectionHeader(title: "Available Delivery Paths")
                            
                            Spacer()
                            
                            Button(action: checkServerPaths) {
                                HStack(spacing: 4) {
                                    if isLoadingServerPaths {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Check")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .disabled(isLoadingServerPaths)
                        }
                        
                        // Path content based on server response
                        pathSectionContent
                    }

                    // Chat-specific stats
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Chat Statistics")
                        
                        HStack(spacing: 20) {
                            StatCard(
                                icon: "bubble.left.and.bubble.right",
                                title: "Messages",
                                value: "\(getMessageCount())",
                                color: .blue
                            )
                            
                            StatCard(
                                icon: "star.fill",
                                title: "Favorite",
                                value: currentChat.isFavorite ? "Yes" : "No",
                                color: currentChat.isFavorite ? .yellow : .gray
                            )
                        }
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            showingEditSheet = true
                        }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Edit Contact")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Contact")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top)
                }
                .padding()
            }
            .navigationTitle("Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ModifiedAddContactView(existingContact: contact) { updatedContact in
                updateChatWithContact(updatedContact)
            }
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteContact()
            }
        } message: {
            Text("Are you sure you want to delete \(currentChat.name)? This will remove the contact but preserve your chat history.")
        }
        .onAppear {
            // Auto-check server paths when view appears
            checkServerPaths()
        }
    }
    
    // MARK: - Path Content Views
    
    private var pathSectionContent: some View {
        Group {
            if isLoadingServerPaths {
                loadingView
            } else if lastServerCheck != nil && serverPaths.isEmpty {
                privatePathsView
            } else if lastServerCheck == nil {
                unknownPathsView
            } else if !serverPaths.isEmpty {
                activePathsView
            }
        }
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Checking contact's available paths...")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var privatePathsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash.circle")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            
            Text("No paths available")
                .font(.headline)
                .foregroundColor(.orange)
                .fontWeight(.medium)
            
            Text("This contact hasn't enabled any delivery paths or they may not be using WindTexter")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var unknownPathsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30))
                .foregroundColor(.gray)
            
            Text("Path availability unknown")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Check what delivery paths this contact has available")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var activePathsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Available Paths")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                Spacer()
                
                if let lastCheck = lastServerCheck {
                    Text(formatCheckTime(lastCheck))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(serverPaths, id: \.self) { path in
                    ServerActivePathCard(path: path, contact: contact)
                }
            }
            
            Text("These paths are automatically shared by \(currentChat.name)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Server Path Checking Functions
    
    private func checkServerPaths() {
        guard let email = currentChat.email else {
            print("⚠️ Cannot check server paths - no email for contact")
            serverPaths = []
            lastServerCheck = Date()
            return
        }
        
        isLoadingServerPaths = true
        
        fetchRecipientPathConfiguration(email: email) { paths in
            DispatchQueue.main.async {
                self.serverPaths = paths
                self.lastServerCheck = Date()
                self.isLoadingServerPaths = false
                
                print("🔍 Server path check complete for chat contact:")
                print("   Contact: \(self.currentChat.name)")
                print("   Email: \(email)")
                print("   Server reported paths: \(paths)")
                
                if paths.isEmpty {
                    print("🚫 Contact has no paths enabled")
                } else {
                    print("✅ Contact has available paths: \(paths)")
                }
                
                // Cache the results (including empty arrays)
                self.cacheServerPaths(paths)
            }
        }
    }
    
    private func fetchRecipientPathConfiguration(email: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/get_user_path_config") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "email": email.lowercased()
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Failed to fetch recipient paths: \(error)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("❌ No data received from server")
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📡 Server response: \(json)")
                    
                    if let paths = json["enabled_paths"] as? [String] {
                        print("✅ Successfully got recipient paths: \(paths)")
                        completion(paths)
                    } else {
                        print("⚠️ No enabled_paths in response")
                        completion([])
                    }
                } else {
                    print("❌ Failed to parse server response")
                    completion([])
                }
            } catch {
                print("❌ JSON parsing error: \(error)")
                completion([])
            }
        }.resume()
    }
    
    private func cacheServerPaths(_ paths: [String]) {
        let key = "serverPaths-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        UserDefaults.standard.set(paths, forKey: key)
        
        let timeKey = "serverPathsTime-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        UserDefaults.standard.set(Date(), forKey: timeKey)
    }
    
    private func formatCheckTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getMessageCount() -> Int {
        let key = "savedMessages-\(currentChat.id.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let savedMessages = try? JSONDecoder().decode([Message].self, from: data) else {
            return 0
        }
        
        let validMessages = savedMessages.filter { message in
            let hasRealText = !(message.realText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasCoverText = !(message.coverText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasImage = message.imageData != nil
            
            return hasRealText || hasCoverText || hasImage
        }
        
        return validMessages.count
    }
    
    private func updateChatWithContact(_ updatedContact: Contact) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index].phoneNumber = updatedContact.phoneNumber
            chats[index].email = updatedContact.email
        }
    }
    
    private func deleteContact() {
        let chatIDToDelete = currentChat.id
        let chatNameToDelete = currentChat.name
        let chatPhoneToDelete = currentChat.phoneNumber
        let chatEmailToDelete = currentChat.email
        
        print("🗑️ Starting deletion of contact: \(chatNameToDelete)")
        
        // Clean up UserDefaults data
        let messageKey = "savedMessages-\(chatIDToDelete.uuidString)"
        UserDefaults.standard.removeObject(forKey: messageKey)
        
        let pathsKey = "availablePaths-\(chatPhoneToDelete ?? chatEmailToDelete ?? "unknown")"
        UserDefaults.standard.removeObject(forKey: pathsKey)
        
        // Clean up message store data
        messageStore.messagesPerChat.removeValue(forKey: chatIDToDelete)
        messageStore.loadedMessageIDs.removeValue(forKey: chatIDToDelete)
        
        // Remove from chats array
        if let indexToRemove = chats.firstIndex(where: { $0.id == chatIDToDelete }) {
            chats.remove(at: indexToRemove)
        }
        
        print("🗑️ Successfully deleted contact: \(chatNameToDelete)")
        dismiss()
    }
}

// Supporting view for chat statistics
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct MessageBubble: View {
    let message: Message
    let showRealMessage: Bool

    init(message: Message, showRealMessage: Bool) {
        self.message = message
        self.showRealMessage = showRealMessage
        
        // Debug print
        print("🔍 MessageBubble for message \(message.id.uuidString.prefix(8)):")
        print("   Has imageData: \(message.imageData != nil)")
        if let imageData = message.imageData {
            print("   Image size: \(imageData.count) bytes")
            print("   Can create UIImage: \(UIImage(data: imageData) != nil)")
        }
        print("   realText: '\(message.realText ?? "nil")'")
        print("   coverText: '\(message.coverText ?? "nil")'")
        print("   showRealMessage: \(showRealMessage)")
    }

    var body: some View {
        let text = message.displayText(showRealMessage: showRealMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        
        let _ = debugPrint("🎨 MessageBubble rendering - text: '\(text)', hasImage: \(message.imageData != nil)")

        return Group {
            if let imageData = message.imageData,
               let uiImage = UIImage(data: imageData) {
                let _ = debugPrint("  Rendering image bubble")
                VStack(alignment: .leading, spacing: 5) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 250)
                        .cornerRadius(12)

                    if !text.isEmpty && text != "📸 Image" && (showRealMessage || !isBitstream(text)) {
                        let _ = debugPrint("📝 Also showing text: '\(text)'")
                        Text(text)
                            .padding(8)
                            .background(message.isSentByCurrentUser ? Color.blue : Color.gray.opacity(0.45))
                            .foregroundColor(message.isSentByCurrentUser ? .white : .primary)
                            .cornerRadius(12)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    } else {
                        let _ = debugPrint("🚫 Not showing text - isEmpty: \(text.isEmpty), isImagePlaceholder: \(text == "📸 Image"), showReal: \(showRealMessage), isBitstream: \(isBitstream(text))")
                    }
                }
            } else {
                let _ = debugPrint("❌ Not rendering image - hasImageData: \(message.imageData != nil), canCreateUIImage: \(message.imageData != nil ? UIImage(data: message.imageData!) != nil : false)")
                if !text.isEmpty {
                    let _ = debugPrint("📝 Rendering text-only bubble: '\(text)'")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(text.isEmpty ? "[Empty Message]" : text)
                            .padding(12)
                            .background(message.isSentByCurrentUser ? Color.blue : Color.gray.opacity(0.45))
                            .foregroundColor(message.isSentByCurrentUser ? .white : .primary)
                            .cornerRadius(16)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    let _ = debugPrint("🚫 Not rendering anything - no text and no valid image")
                    EmptyView()
                }
            }
        }
    }
    
    private func debugPrint(_ message: String) -> Void {
        print(message)
        return ()
    }
    
    private func isBitstream(_ text: String) -> Bool {
        // Check if the text consists only of 0s and 1s (with possible spaces)
        let cleanedText = text.replacingOccurrences(of: " ", with: "")
        return !cleanedText.isEmpty && cleanedText.allSatisfy { $0 == "0" || $0 == "1" }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return self.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
