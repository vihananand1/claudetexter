import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var countryCode: String? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            self.countryCode = placemarks?.first?.isoCountryCode
        }
        manager.stopUpdatingLocation()
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// CRITICAL FIX: Enhanced cross-channel duplicate detection extensions
extension Message {
    // ENHANCED: Create a content-based signature that can detect cross-format duplicates
    func createCrossChannelSignature() -> String {
        var components: [String] = []
        
        // Normalize timestamp to nearest 30-second window to catch near-simultaneous messages
        let normalizedTimestamp = normalizeTimestampToWindow(timestamp, windowSeconds: 30)
        components.append("time:\(normalizedTimestamp)")
        
        // CRITICAL: Normalize content for cross-format detection
        let normalizedContent = normalizeContent()
        if !normalizedContent.isEmpty {
            components.append("content:\(normalizedContent)")
        }
        
        // Include sender information (more flexible matching)
        let normalizedSender = normalizeSender()
        components.append("sender:\(normalizedSender)")
        
        // Include delivery path
        components.append("path:\(deliveryPath ?? "unknown")")
        
        let combined = components.joined(separator: "|")
        return String(combined.hashValue)
    }
    
    func normalizeContent() -> String {
        // CRITICAL: Try to normalize content across different formats
        
        // If we have real text, use that as the canonical content
        if let realText = realText?.trimmingCharacters(in: .whitespacesAndNewlines), !realText.isEmpty {
            return realText.lowercased()
        }
        
        // If we have cover text that's NOT a bitstream, use that
        if let coverText = coverText?.trimmingCharacters(in: .whitespacesAndNewlines), !coverText.isEmpty {
            // Check if it's a bitstream (only 0s and 1s)
            if coverText.allSatisfy({ $0 == "0" || $0 == "1" }) {
                // For bitstreams, use a hash of the content to normalize length variations
                return "bitstream_\(coverText.count)_\(coverText.hashValue)"
            } else {
                return coverText.lowercased()
            }
        }
        
        // If we have image data, use its size as identifier
        if let imageData = imageData {
            return "image_\(imageData.count)"
        }
        
        return "empty"
    }
    
    func normalizeSender() -> String {
        // Try to extract the core sender identifier, ignoring prefixes
        if let senderID = senderID {
            // Remove common prefixes that might vary between sources
            let cleanSender = senderID
                .replacingOccurrences(of: "windtexter_", with: "")
                .replacingOccurrences(of: "sender_", with: "")
                .lowercased()
            return cleanSender
        }
        return "unknown"
    }
    
    private func normalizeTimestampToWindow(_ timestamp: String, windowSeconds: Int) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: timestamp) {
            // Round to nearest window
            let timeInterval = date.timeIntervalSince1970
            let windowedInterval = round(timeInterval / Double(windowSeconds)) * Double(windowSeconds)
            let windowedDate = Date(timeIntervalSince1970: windowedInterval)
            return isoFormatter.string(from: windowedDate)
        } else {
            // Try without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: timestamp) {
                let timeInterval = date.timeIntervalSince1970
                let windowedInterval = round(timeInterval / Double(windowSeconds)) * Double(windowSeconds)
                let windowedDate = Date(timeIntervalSince1970: windowedInterval)
                return isoFormatter.string(from: windowedDate)
            }
            return timestamp
        }
    }
}

// ENHANCED: ChatMessagesStore with cross-channel duplicate detection
extension ChatMessagesStore {
    func isDuplicateCrossChannel(_ newMessage: Message, in chat: Chat) -> Bool {
        let existingMessages = messagesPerChat[chat.id] ?? []
        
        // Check by ID first (exact match)
        if existingMessages.contains(where: { $0.id == newMessage.id }) {
            print("🔄 Duplicate detected by ID: \(newMessage.id.uuidString.prefix(8))")
            return true
        }
        
        // CRITICAL: Check by cross-channel signature
        let newSignature = newMessage.createCrossChannelSignature()
        let existingSignatures = Set(existingMessages.map { $0.createCrossChannelSignature() })
        
        if existingSignatures.contains(newSignature) {
            print("🔄 Cross-channel duplicate detected by signature: \(newSignature)")
            return true
        }
        
        // ENHANCED: Additional cross-format duplicate detection
        let newTimestamp = parseTimestamp(newMessage.timestamp)
        
        for existing in existingMessages {
            let existingTimestamp = parseTimestamp(existing.timestamp)
            let timeDifference = abs(newTimestamp.timeIntervalSince(existingTimestamp))
            
            // If timestamps are within 60 seconds, check for content similarity
            if timeDifference <= 60 {
                
                // Case 1: Same real text content
                if let newReal = newMessage.realText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let existingReal = existing.realText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !newReal.isEmpty && !existingReal.isEmpty && newReal == existingReal {
                    print("🔄 Cross-channel duplicate: same real text within 60s")
                    return true
                }
                
                // Case 2: One has real text, other has bitstream (different processing stages)
                if let newReal = newMessage.realText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let existingCover = existing.coverText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !newReal.isEmpty && !existingCover.isEmpty,
                   existingCover.allSatisfy({ $0 == "0" || $0 == "1" }) && existingCover.count > 10 {
                    print("🔄 Cross-channel duplicate: real text vs bitstream within 60s")
                    return true
                }
                
                // Case 3: Reverse - bitstream vs real text
                if let newCover = newMessage.coverText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let existingReal = existing.realText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !newCover.isEmpty && !existingReal.isEmpty,
                   newCover.allSatisfy({ $0 == "0" || $0 == "1" }) && newCover.count > 10 {
                    print("🔄 Cross-channel duplicate: bitstream vs real text within 60s")
                    return true
                }
                
                // Case 4: Same cover text
                if let newCover = newMessage.coverText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let existingCover = existing.coverText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !newCover.isEmpty && !existingCover.isEmpty && newCover == existingCover {
                    print("🔄 Cross-channel duplicate: same cover text within 60s")
                    return true
                }
                
                // Case 5: Image data similarity
                if let newImageData = newMessage.imageData,
                   let existingImageData = existing.imageData,
                   newImageData.count == existingImageData.count {
                    print("🔄 Cross-channel duplicate: same image size within 60s")
                    return true
                }
                
                // Case 6: Check sender similarity with timing
                let newSender = newMessage.normalizeSender()
                let existingSender = existing.normalizeSender()
                
                if newSender == existingSender && timeDifference <= 30 {
                    // Same sender within 30 seconds - check if content is related
                    let hasContentSimilarity = checkContentSimilarity(newMessage, existing)
                    if hasContentSimilarity {
                        print("🔄 Cross-channel duplicate: same sender + similar content within 30s")
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    private func checkContentSimilarity(_ message1: Message, _ message2: Message) -> Bool {
        let content1 = message1.normalizeContent()
        let content2 = message2.normalizeContent()
        
        // If one is empty and other isn't, not similar
        if content1.isEmpty || content2.isEmpty {
            return content1 == content2
        }
        
        // Direct match
        if content1 == content2 {
            return true
        }
        
        // Bitstream similarity (same pattern or similar length)
        if content1.hasPrefix("bitstream_") && content2.hasPrefix("bitstream_") {
            return true // Assume bitstreams from same timeframe are related
        }
        
        // Text similarity (simple check) - FIX: Use proper CharacterSet
        if !content1.hasPrefix("bitstream_") && !content2.hasPrefix("bitstream_") {
            let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            let words1 = Set(content1.components(separatedBy: separators))
            let words2 = Set(content2.components(separatedBy: separators))
            let intersection = words1.intersection(words2)
            let union = words1.union(words2)
            
            // If more than 50% word overlap, consider similar
            if !union.isEmpty && Double(intersection.count) / Double(union.count) > 0.5 {
                return true
            }
        }
        
        return false
    }
    
    // ENHANCED: Updated addMessage with cross-channel duplicate detection
    func addMessageEnhanced(_ message: Message, to chat: Chat) {
        // Use enhanced cross-channel duplicate detection
        guard !isDuplicateCrossChannel(message, in: chat) else {
            print("🔄 ChatMessagesStore: Skipping cross-channel duplicate message")
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

        // Track ID after successfully adding
        loadedMessageIDs[chat.id, default: []].insert(message.id)

        latestChange = UUID()
        save(chat: chat)

        print("✅ ChatMessagesStore: Added message and sorted chronologically. Total count: \(sortedMessages.count)")
    }
}

struct HomeView: View {
    @EnvironmentObject var messageStore: ChatMessagesStore
    @State private var activePaths: [String] = []
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedFilter: String = "All"
    @AppStorage("isSignedInToGmail") private var isSignedInToGmail: Bool = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @StateObject var locationManager = LocationManager()
    @State private var searchQuery: String = ""
    @State private var chats: [Chat] = []

    // FOCUS ONLY ON EMAIL
    let regionToPaths: [String: [String]] = [
        "US": ["Email"],
        "GB": ["Email"],
        "IN": ["Email"],
        "BR": ["Email"],
        "DE": ["Email"],
        "CN": ["Email"],
        "default": ["Email"]
    ]

    @Environment(\.colorScheme) var colorScheme
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("showRealMessage") private var showRealMessage: Bool = true
    @State private var isInChat: Bool = false
    @State private var refreshToggle = false
    @State private var lastUpdateTime = Date()
    @State private var backendPollingTimer: Timer?
    @State private var showingAddContact = false
    @State private var contacts: [Contact] = []
    @AppStorage("hasImportedContacts") private var hasImportedContacts = false
    @AppStorage("selectedPathForChat") private var selectedPathForChatRaw: String = ""
    
    // CRITICAL FIX: Track which chat is currently being viewed
    @State private var currentlyViewedChatId: UUID? = nil
    
    // CRITICAL FIX: Track processed message IDs and cross-channel signatures to prevent re-processing
    @State private var processedMessageIds: Set<String> = []
    
    // CRITICAL FIX: Track last processed timestamp per chat to prevent duplicate unread increments
    @State private var lastProcessedTimestamps: [UUID: Date] = [:]
    
    // CRITICAL FIX: Track when user was last active to prevent stale unread increments
    @State private var lastUserActiveTime = Date()

    var body: some View {
        TabView {
            mainChatTab
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("Chats")
                }

            SettingsView(isDarkMode: $isDarkMode)
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
        }
        .background(backgroundColor)
        .onChange(of: isInChat) { inChat in
            UIApplication.shared.windows.first?.rootViewController?.tabBarController?.tabBar.isHidden = inChat
            
            // CRITICAL FIX: When user exits any chat, clear the currently viewed chat ID
            if !inChat {
                currentlyViewedChatId = nil
                print("🚪 User exited chat - cleared currentlyViewedChatId")
            }
        }
        // FIX: Remove broad .onTapGesture that conflicts with other gestures
        // Track user activity through app lifecycle events instead
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            lastUserActiveTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            lastUserActiveTime = Date()
        }
        // CRITICAL FIX: Properly respond to messageStore updates
        .onReceive(messageStore.$latestChange) { _ in
            DispatchQueue.main.async {
                print("🔄 HomeView received messageStore update - refreshing UI")
                updateAllChatPreviews() // Update all previews when messages change
                lastUpdateTime = Date()
                refreshToggle.toggle()
            }
        }
    }

    private var mainChatTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: UIScreen.main.bounds.height * 0.015)
                        searchBar
                        filterButtons
                        chatList
                    }
                    .padding(.top, 10)
                    .background(backgroundColor)
                }

                footerView
            }
            .background(backgroundColor)
            .padding(.bottom, 40)
            .navigationTitle("WindTexter")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // FIX: Improve button responsiveness
                    Button(action: {
                        lastUserActiveTime = Date() // Track user activity
                        showingAddContact = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle()) // FIX: Explicit button style
                    .contentShape(Rectangle()) // FIX: Ensure entire area is tappable
                }
            }
            .background(backgroundColor)
            .onAppear {
                setupPollingAndData()
            }
            .onDisappear {
                cleanupTimers()
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView { newContact in
                    addNewChat(from: newContact)
                }
            }
        }
    }
    
    // CRITICAL FIX: Centralized function to update all chat previews
    private func updateAllChatPreviews() {
        print("🔄 Updating all chat previews...")
        
        for index in chats.indices {
            let chat = chats[index]
            let messages = messageStore.messagesPerChat[chat.id] ?? []
            
            // Find the most recent valid message
            let validMessages = messages.filter { message in
                let hasRealText = !(message.realText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let hasCoverText = !(message.coverText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let hasImage = message.imageData != nil
                return hasRealText || hasCoverText || hasImage
            }
            
            let sortedMessages = validMessages.sorted { $0.timestamp > $1.timestamp }
            
            if let latestMessage = sortedMessages.first {
                updateChatPreviewAtIndex(index, with: latestMessage)
            }
        }
    }
    
    // CRITICAL FIX: Update individual chat preview WITHOUT changing unread count
    private func updateChatPreviewAtIndex(_ index: Int, with message: Message) {
        print("🎯 Updating preview for chat at index \(index): \(chats[index].name)")
        
        // Handle image messages
        if message.imageData != nil {
            chats[index].realMessage = message.realText?.isEmpty == false ? message.realText! : "📸 Image"
            chats[index].coverMessage = "📸 Image"
        }
        // Handle sent messages (we have both real and cover text)
        else if message.isSentByCurrentUser {
            chats[index].realMessage = message.realText ?? ""
            chats[index].coverMessage = message.coverText ?? ""
        }
        // Handle received messages
        else {
            if let realText = message.realText, !realText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chats[index].realMessage = realText
                chats[index].coverMessage = message.coverText ?? realText
            } else {
                chats[index].realMessage = message.coverText ?? ""
                chats[index].coverMessage = message.coverText ?? ""
            }
        }
        
        // Update timestamp
        chats[index].time = message.formattedTimestamp()
        
        print("   Updated preview - realMessage: '\(chats[index].realMessage.prefix(30))...'")
        print("   Updated preview - coverMessage: '\(chats[index].coverMessage.prefix(30))...'")
        print("   Updated preview - unreadCount: \(chats[index].unreadCount) (NOT MODIFIED)")
    }
    
    // CRITICAL FIX: Better polling setup with proper unread counting
    private func setupPollingAndData() {
        // Initialize contacts and other setup
        if UserDefaults.standard.bool(forKey: "isSignedInToGmail") {
            isSignedInToGmail = true
        }
        print("🧪 Synced isSignedInToGmail: \(isSignedInToGmail)")
        
        if !hasImportedContacts {
            importContacts()
        }
        
        // CRITICAL FIX: Initialize last processed timestamps for all chats
        for chat in chats {
            saveInitialMessageForChatIfNeeded(chat)
            messageStore.load(for: chat) // Ensure messages are loaded
            
            // Initialize last processed timestamp to prevent counting existing messages as new
            if lastProcessedTimestamps[chat.id] == nil {
                let messages = messageStore.messagesPerChat[chat.id] ?? []
                if let latestMessage = messages.max(by: { parseTimestamp($0.timestamp) < parseTimestamp($1.timestamp) }) {
                    lastProcessedTimestamps[chat.id] = parseTimestamp(latestMessage.timestamp)
                    print("📊 Initialized last processed timestamp for \(chat.name): \(parseTimestamp(latestMessage.timestamp))")
                } else {
                    lastProcessedTimestamps[chat.id] = Date()
                    print("📊 Initialized last processed timestamp for \(chat.name) to now (no messages)")
                }
            }
        }
        
        // Start backend polling timer with SEQUENTIAL polling (not simultaneous)
        startBackendPolling() // This now uses the new sequential approach
    }
    
    // CRITICAL FIX: More frequent polling and better unread handling
    private func startBackendPolling() {
        backendPollingTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in // Increased interval for sequential polling
            print("🏠 HomePage sequential polling at \(Date())")
            print("🔍 Checking \(self.chats.count) chats")
            
            guard let currentUserEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email else {
                print("⚠️ No current user email available for polling")
                return
            }
            
            print("📡 Phase 1: Backend polling for current user: \(currentUserEmail)")
            
            // Phase 1: Backend polling first
            self.pollBackendForNewMessages(currentUserEmail: currentUserEmail) {
                // Phase 2: Gmail polling (only after backend completes)
                if self.isSignedInToGmail {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("📡 Phase 2: Gmail polling (after backend completion)")
                        self.pollGmailForWindTexterMessagesWithRateLimit(currentUserEmail: currentUserEmail)
                    }
                }
            }
        }
    }
    
    private func pollBackendForNewMessages(currentUserEmail: String, completion: @escaping () -> Void = {}) {
        let dispatchGroup = DispatchGroup()
        
        for (chatIndex, chat) in chats.enumerated() {
            guard let chatPartnerEmail = chat.email, !chatPartnerEmail.isEmpty else {
                print("⚠️ Skipping chat \(chat.name) - no email")
                continue
            }
            
            print("🔍 Backend: Fetching conversation between \(currentUserEmail) and \(chatPartnerEmail)")
            
            dispatchGroup.enter()
            BackendAPI.fetchConversationMessages(
                for: "send_email",
                currentUserEmail: currentUserEmail,
                chatPartnerEmail: chatPartnerEmail,
                chatID: chat.id
            ) { backendMessages in
                print("📡 Backend: Got \(backendMessages.count) messages for conversation")
                
                DispatchQueue.main.async {
                    // Mark messages with source for better duplicate detection
                    for message in backendMessages {
                        message.messageSource = "backend"
                    }
                    
                    self.processNewMessagesEnhanced(backendMessages, for: chat, at: chatIndex, currentUserEmail: currentUserEmail)
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            completion()
        }
    }
    
    // CRITICAL FIX: Enhanced message processing with cross-channel duplicate detection
    private func processNewMessagesEnhanced(_ backendMessages: [Message], for chat: Chat, at chatIndex: Int, currentUserEmail: String) {
           messageStore.load(for: chat)
           
           // Get last processed timestamp for this chat
           let lastProcessedTime = lastProcessedTimestamps[chat.id] ?? Date.distantPast
           
           let trulyNewMessages = backendMessages.filter { newMessage in
               let messageId = newMessage.id.uuidString
               let messageTimestamp = parseTimestamp(newMessage.timestamp)
               
               // CRITICAL FIX: Normalize delivery path immediately
               newMessage.deliveryPath = normalizeDeliveryPath(newMessage.deliveryPath ?? "email")
               print("📍 Normalized message delivery path: '\(newMessage.deliveryPath ?? "nil")'")
               
               // Skip if we've already processed this message ID
               if processedMessageIds.contains(messageId) {
                   print("🔄 Already processed message ID: \(messageId.prefix(8)), skipping")
                   return false
               }
               
               // Enhanced: Use cross-channel duplicate detection
               if messageStore.isDuplicateCrossChannel(newMessage, in: chat) {
                   print("🔄 Cross-channel duplicate detected, skipping")
                   processedMessageIds.insert(messageId)
                   return false
               }
               
               // Skip if message timestamp is before last processed time
               if messageTimestamp <= lastProcessedTime {
                   print("🔄 Message timestamp \(messageTimestamp) is before last processed \(lastProcessedTime), skipping")
                   processedMessageIds.insert(messageId)
                   return false
               }
               
               let isValid = validateMessageForConversation(newMessage, chat: chat, currentUserEmail: currentUserEmail)
               
               if !isValid {
                   return false
               }
               
               return true
           }
        
        if !trulyNewMessages.isEmpty {
            print("📥 Backend: Found \(trulyNewMessages.count) truly new messages for \(chat.name)")
            
            // CRITICAL FIX: Check if user is CURRENTLY viewing this specific chat
            let isCurrentlyViewingThisChat = isInChat && (currentlyViewedChatId == chat.id)
            
            var hasNewReceivedMessages = false
            var latestMessage: Message?
            var newReceivedCount = 0
            var latestTimestamp = lastProcessedTimestamps[chat.id] ?? Date.distantPast
            
            for message in trulyNewMessages {
                let messageTimestamp = parseTimestamp(message.timestamp)
                
                // Track this message as processed IMMEDIATELY to prevent reprocessing
                processedMessageIds.insert(message.id.uuidString)
                
                // CRITICAL: Also track by cross-channel signature
                let crossSignature = message.createCrossChannelSignature()
                processedMessageIds.insert(crossSignature)
                
                messageStore.addMessageEnhanced(message, to: chat)
                
                // Update latest timestamp
                if messageTimestamp > latestTimestamp {
                    latestTimestamp = messageTimestamp
                }
                
                // CRITICAL FIX: Only count as "new received" if:
                // 1. Not sent by current user
                // 2. User is NOT currently viewing this specific chat
                // 3. Message timestamp is newer than when user was last active
                if !message.isSentByCurrentUser {
                    let timeSinceUserActive = Date().timeIntervalSince(lastUserActiveTime)
                    let messageAge = Date().timeIntervalSince(messageTimestamp)
                    
                    // Only count as new if message is recent (within 30 seconds) or user hasn't been active recently
                    let shouldCountAsNew = messageAge < 30 || timeSinceUserActive > 60
                    
                    if !isCurrentlyViewingThisChat && shouldCountAsNew {
                        hasNewReceivedMessages = true
                        newReceivedCount += 1
                        print("📨 Found new received message from \(chat.email ?? "unknown") - user NOT viewing this chat")
                    } else {
                        if isCurrentlyViewingThisChat {
                            print("👀 User is currently viewing \(chat.name), message auto-read - NO unread count increment")
                        } else {
                            print("⏰ Message too old or user was recently active, not counting as new unread")
                        }
                    }
                }
                
                // Track latest message for preview update
                if latestMessage == nil || message.timestamp > latestMessage!.timestamp {
                    latestMessage = message
                }
            }
            
            // CRITICAL FIX: Update last processed timestamp for this chat
            lastProcessedTimestamps[chat.id] = latestTimestamp
            
            // CRITICAL FIX: Only update preview and unread count if user is NOT currently viewing this chat
            if !isCurrentlyViewingThisChat {
                // Update unread counter for received messages
                if hasNewReceivedMessages {
                    chats[chatIndex].unreadCount += newReceivedCount
                    print("📈 Updated unread count for \(chat.name): \(chats[chatIndex].unreadCount)")
                }
                
                // Update chat preview with latest message
                if let latestMessage = latestMessage {
                    updateChatPreviewAtIndex(chatIndex, with: latestMessage)
                    print("🔄 Updated chat preview for \(chat.name)")
                }
            } else {
                print("👀 User is viewing \(chat.name) - SKIPPING preview and unread count updates")
            }
            
            // Force UI refresh
            DispatchQueue.main.async {
                self.refreshToggle.toggle()
                self.lastUpdateTime = Date()
            }
        }
    }

    // Gmail polling function for HomeView.swift with enhanced duplicate detection
    private func pollGmailForWindTexterMessagesWithRateLimit(currentUserEmail: String) {
        // Check if we've hit rate limits recently
        let rateLimitKey = "gmailRateLimitUntil"
        if let rateLimitUntilString = UserDefaults.standard.string(forKey: rateLimitKey),
           let rateLimitUntil = ISO8601DateFormatter().date(from: rateLimitUntilString),
           Date() < rateLimitUntil {
            print("⏰ Gmail: Still under rate limit until \(rateLimitUntil), skipping polling")
            return
        }
        
        guard let accessToken = UserDefaults.standard.string(forKey: "gmailAccessToken") else {
            print("⚠️ No Gmail access token available")
            return
        }
        
        print("📬 Gmail: Polling for WindTexter service emails (rate-limited)")

        GmailService.fetchEmailIDsFromSender(
            accessToken: accessToken,
            senderEmail: "windtexter@gmail.com"
        ) { ids in
            print("📧 Gmail: Found \(ids.count) WindTexter service emails")
            
            for id in ids {
                GmailService.fetchEmailBody(id: id, token: accessToken) { body, timestampString, sender, recipient, customHeaders in
                    guard let body = body, !body.isEmpty else {
                        return
                    }
                    
                    // Validate this is from WindTexter service TO current user
                    guard let sender = sender?.lowercased(),
                          sender.contains("windtexter@gmail.com"),
                          let recipient = recipient?.lowercased(),
                          recipient.contains(currentUserEmail.lowercased()) else {
                        return
                    }
                    
                    print("✅ Gmail: Processing WindTexter message")
                    print("📧 Headers: \(customHeaders ?? [:])")
                    
                    // CRITICAL: Get real sender from headers
                    let realSender = customHeaders?["realSender"] ?? customHeaders?["replyTo"]
                    let chatIDString = customHeaders?["chatID"]
                    let senderID = customHeaders?["senderID"]
                    
                    // ENHANCED: Auto-create chat if needed
                    var targetChat: Chat? = self.findOrCreateChatForSender(
                        realSender: realSender,
                        chatIDString: chatIDString,
                        currentUserEmail: currentUserEmail
                    )
                    
                    guard let chat = targetChat else {
                        print("❌ Gmail: Could not find or create chat for message")
                        return
                    }
                    
                    // CRITICAL FIX: Check if user is currently viewing this specific chat
                    let isCurrentlyViewingThisChat = self.isInChat && (self.currentlyViewedChatId == chat.id)
                    
                    // CRITICAL FIX: Enhanced duplicate detection for Gmail messages
                    let tempMessage = Message(
                        realText: nil,
                        coverText: body,
                        isSentByCurrentUser: false,
                        timestamp: timestampString ?? ISO8601DateFormatter().string(from: Date()),
                        deliveryPath: "email"
                    )
                    tempMessage.senderID = senderID ?? "windtexter_\(realSender ?? "unknown")"
                    tempMessage.messageSource = "gmail"

                    // ENHANCED: Use cross-channel duplicate detection
                    if messageStore.isDuplicateCrossChannel(tempMessage, in: chat) {
                        print("🔄 Gmail: Cross-channel duplicate message detected, skipping")
                        return
                    }

                    // Check if we've processed this before using cross-channel signature
                    let crossSignature = tempMessage.createCrossChannelSignature()
                    if self.processedMessageIds.contains(crossSignature) {
                        print("🔄 Gmail: Already processed this message by cross-signature, skipping")
                        return
                    }

                    // CRITICAL FIX: Check timestamp to prevent counting old messages as new
                    let messageTimestamp = parseTimestamp(timestampString ?? ISO8601DateFormatter().string(from: Date()))
                    let lastProcessedTime = self.lastProcessedTimestamps[chat.id] ?? Date.distantPast

                    if messageTimestamp <= lastProcessedTime {
                        print("🔄 Gmail: Message timestamp is before last processed, skipping unread increment")
                        self.processedMessageIds.insert(crossSignature)
                        return
                    }
                    
                    // Decode and add message
                    if body.allSatisfy({ $0 == "0" || $0 == "1" }) {
                        // Bitstream - decode it
                        GmailManager.decodeCoverChunks([body]) { decodedText in
                            DispatchQueue.main.async {
                                let newMessage = Message(
                                    realText: decodedText ?? body,
                                    coverText: body,
                                    isSentByCurrentUser: false,
                                    timestamp: timestampString ?? ISO8601DateFormatter().string(from: Date()),
                                    deliveryPath: "email"
                                )
                                
                                newMessage.senderID = senderID ?? "windtexter_\(realSender ?? "unknown")"
                                newMessage.messageSource = "gmail"
                                
                                // Track this message using both methods
                                self.processedMessageIds.insert(newMessage.id.uuidString)
                                self.processedMessageIds.insert(newMessage.createCrossChannelSignature())
                                
                                self.messageStore.addMessageEnhanced(newMessage, to: chat)
                                
                                // Update last processed timestamp
                                self.lastProcessedTimestamps[chat.id] = messageTimestamp
                                
                                if let index = self.chats.firstIndex(where: { $0.id == chat.id }) {
                                    // CRITICAL FIX: Check if user is currently viewing this specific chat
                                    let isCurrentlyViewingThisChat = self.isInChat && (self.currentlyViewedChatId == chat.id)
                                    
                                    if !isCurrentlyViewingThisChat {
                                        // CRITICAL FIX: Additional check for user activity
                                        let timeSinceUserActive = Date().timeIntervalSince(self.lastUserActiveTime)
                                        let messageAge = Date().timeIntervalSince(messageTimestamp)
                                        let shouldCountAsNew = messageAge < 30 || timeSinceUserActive > 60
                                        
                                        if shouldCountAsNew {
                                            // Only update preview and unread count if user is NOT viewing this chat
                                            self.updateChatPreviewAtIndex(index, with: newMessage)
                                            self.chats[index].unreadCount += 1
                                            print("📈 Gmail: Updated preview and incremented unread count for \(chat.name)")
                                        } else {
                                            print("⏰ Gmail: Message too old or user recently active, not counting as new")
                                        }
                                    } else {
                                        print("👀 Gmail: User viewing \(chat.name), message auto-read - NO updates")
                                    }
                                }
                                
                                print("✅ Gmail: Added decoded message to \(chat.name)")
                                self.refreshToggle.toggle()
                            }
                        }
                    } else {
                        // Plain text
                        DispatchQueue.main.async {
                            let newMessage = Message(
                                realText: body,
                                coverText: body,
                                isSentByCurrentUser: false,
                                timestamp: timestampString ?? ISO8601DateFormatter().string(from: Date()),
                                deliveryPath: "email"
                            )
                            
                            newMessage.senderID = senderID ?? "windtexter_\(realSender ?? "unknown")"
                            newMessage.messageSource = "gmail"
                            
                            // Track this message using both methods
                            self.processedMessageIds.insert(newMessage.id.uuidString)
                            self.processedMessageIds.insert(newMessage.createCrossChannelSignature())
                            
                            self.messageStore.addMessageEnhanced(newMessage, to: chat)
                            
                            // Update last processed timestamp
                            self.lastProcessedTimestamps[chat.id] = messageTimestamp
                            
                            if let index = self.chats.firstIndex(where: { $0.id == chat.id }) {
                                // CRITICAL FIX: Check if user is currently viewing this specific chat
                                let isCurrentlyViewingThisChat = self.isInChat && (self.currentlyViewedChatId == chat.id)
                                
                                if !isCurrentlyViewingThisChat {
                                    // CRITICAL FIX: Additional check for user activity
                                    let timeSinceUserActive = Date().timeIntervalSince(self.lastUserActiveTime)
                                    let messageAge = Date().timeIntervalSince(messageTimestamp)
                                    let shouldCountAsNew = messageAge < 30 || timeSinceUserActive > 60
                                    
                                    if shouldCountAsNew {
                                        // Only update preview and unread count if user is NOT viewing this chat
                                        self.updateChatPreviewAtIndex(index, with: newMessage)
                                        self.chats[index].unreadCount += 1
                                        print("📈 Gmail: Updated preview and incremented unread count for \(chat.name)")
                                    } else {
                                        print("⏰ Gmail: Message too old or user recently active, not counting as new")
                                    }
                                } else {
                                    print("👀 Gmail: User viewing \(chat.name), message auto-read - NO updates")
                                }
                            }
                            
                            print("✅ Gmail: Added plain text message to \(chat.name)")
                            self.refreshToggle.toggle()
                        }
                    }
                }
            }
        }
    }

    // Auto-create chats for incoming messages
    private func findOrCreateChatForSender(realSender: String?, chatIDString: String?, currentUserEmail: String) -> Chat? {
        // Method 1: Find by chat ID
        if let chatIDString = chatIDString, let chatID = UUID(uuidString: chatIDString) {
            if let existingChat = chats.first(where: { $0.id == chatID }) {
                print("🎯 Found existing chat by ID: \(existingChat.name)")
                return existingChat
            }
        }
        
        // Method 2: Find by sender email
        if let realSender = realSender {
            if let existingChat = chats.first(where: { chat in
                guard let chatEmail = chat.email else { return false }
                return chatEmail.lowercased().contains(realSender.lowercased()) ||
                       realSender.lowercased().contains(chatEmail.lowercased())
            }) {
                print("🎯 Found existing chat by email: \(existingChat.name)")
                return existingChat
            }
            
            // AUTO-CREATE: Create new chat for unknown sender
            print("🆕 Creating new chat for sender: \(realSender)")
            
            let senderName = realSender.components(separatedBy: "@").first?.capitalized ?? "Unknown"
            let currentTime = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
            
            let newChat = Chat(
                name: senderName,
                realMessage: "",
                coverMessage: "",
                time: currentTime,
                unreadCount: 0,
                isFavorite: false,
                isNew: true,
                phoneNumber: nil,
                email: realSender
            )
            
            chats.append(newChat)
            print("✅ Created new chat: \(newChat.name) (\(realSender))")
            return newChat
        }
        
        return nil
    }

    // Better message validation with focus on email
    private func validateMessageForConversation(_ message: Message, chat: Chat, currentUserEmail: String) -> Bool {
        print("🔍 Validating message for conversation")
        print("   Message sender_id: \(message.senderID ?? "nil")")
        print("   Current device_id: \(DeviceIDManager.shared.deviceID)")
        print("   Current user email: \(currentUserEmail)")
        print("   Chat partner email: \(chat.email ?? "nil")")
        
        let currentDeviceID = DeviceIDManager.shared.deviceID
        
        // Messages from the conversation endpoint should already be filtered properly
        // This is just additional validation
        
        // If this is a message sent by the current user, it should appear in this chat
        if message.senderID == currentDeviceID {
            print("   ✅ Message sent by current user - including")
            return true
        }
        
        // For received messages, validate they're from the chat partner
        guard let chatPartnerEmail = chat.email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("   ❌ Chat has no email - rejecting message")
            return false
        }
        
        print("   📧 Validating received message for chat partner: \(chatPartnerEmail)")
        
        // The conversation endpoint should have already filtered this properly
        // so we can be more permissive here
        return true
    }

    private var searchBar: some View {
        TextField("Search Chats", text: $searchQuery)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
            .padding(.horizontal, 15)
            .padding(.bottom, 10)
            .onTapGesture {
                // Track user activity when interacting with search
                lastUserActiveTime = Date()
            }
    }

    private var filterButtons: some View {
        HStack {
            FilterButton(title: "All", selectedFilter: $selectedFilter, lastUserActiveTime: $lastUserActiveTime)
            FilterButton(title: "Unread", selectedFilter: $selectedFilter, lastUserActiveTime: $lastUserActiveTime)
            FilterButton(title: "Favorites", selectedFilter: $selectedFilter, lastUserActiveTime: $lastUserActiveTime)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 5)
        .padding(.leading, 15)
        .padding(.bottom, 5)
    }

    // FIX: Simplified chat list with better tap handling
    private var chatList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                let originalIndex = chats.firstIndex(where: { $0.id == chat.id }) ?? index
                
                // FIX: Cleaner NavigationLink without conflicting gestures
                NavigationLink(
                    destination: ChatView(chat: $chats[originalIndex], isInChat: $isInChat, chats: $chats)
                        .onAppear {
                            // Track user activity and chat viewing
                            lastUserActiveTime = Date()
                            markChatAsRead(chat.id)
                            messageStore.load(for: chat)
                            isInChat = true
                            currentlyViewedChatId = chat.id
                            print("🎯 Opened chat: \(chat.name)")
                        }
                ) {
                    VStack(spacing: 0) {
                        ChatRow(chat: chats[originalIndex], searchQuery: searchQuery, showRealMessage: showRealMessage)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(backgroundColor)

                        if index < filteredChats.count - 1 {
                            Divider()
                                .padding(.leading, 74)
                                .background(Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.6))
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle()) // FIX: Ensure proper button style
                .contentShape(Rectangle()) // FIX: Ensure entire area is tappable
            }
        }
        .transition(.opacity)
        .id(selectedFilter + searchQuery + "\(refreshToggle)")
        .animation(.easeInOut(duration: 0.3), value: selectedFilter + searchQuery + "\(refreshToggle)")
        .padding(.top, 5)
    }

    private var footerView: some View {
        Group {
            if selectedFilter == "All" && searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Text("WindTexter offers secure, encrypted messaging")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            }
        }
    }

    private var filteredChats: [Chat] {
        var results = chats

        switch selectedFilter {
        case "Unread":
            results = results.filter { $0.unreadCount > 0 }
        case "Favorites":
            results = results.filter { $0.isFavorite }
        default:
            break
        }

        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let rawQuery = searchQuery.lowercased()
            let query = rawQuery.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)

            results = results.filter { chat in
                let nameMatch = chat.name.lowercased().contains(query)

                if let savedData = UserDefaults.standard.data(forKey: "savedMessages-\(chat.id.uuidString)"),
                   let decodedMessages = try? JSONDecoder().decode([Message].self, from: savedData) {

                    let messageMatch = decodedMessages.contains { message in
                        let rawText = message.displayText(showRealMessage: showRealMessage).lowercased()
                        let normalizedText = rawText.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
                        return normalizedText.contains(query)
                    }

                    return nameMatch || messageMatch
                }

                return nameMatch
            }
        }

        return results
    }
    
    
    // CRITICAL FIX: Proper chat read marking that only marks unread count to 0
    private func markChatAsRead(_ chatId: UUID) {
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            let previousCount = chats[index].unreadCount
            chats[index].unreadCount = 0
            
            print("✅ Marked chat '\(chats[index].name)' as read (was: \(previousCount), now: 0)")
            print("🎯 Chat will not have preview updates while user is viewing it")
            refreshToggle.toggle()
        }
    }
    
    // Helper functions
    private func cleanupTimers() {
        backendPollingTimer?.invalidate()
        backendPollingTimer = nil
        // CRITICAL FIX: Clear tracking when leaving home view
        currentlyViewedChatId = nil
        print("🧹 Cleared currentlyViewedChatId")
    }
    
    private func addNewChat(from contact: Contact) {
        let currentTime = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        
        let newChat = Chat(
            name: contact.name,
            realMessage: "",
            coverMessage: "",
            time: currentTime,
            unreadCount: 0,
            isFavorite: false,
            isNew: true,
            phoneNumber: contact.phoneNumber,
            email: contact.email
        )
        
        chats.append(newChat)
        saveInitialMessageForChatIfNeeded(newChat)
        
        let availablePaths = getAvailablePathsForContact(newChat)
        UserDefaults.standard.set(availablePaths, forKey: "availablePaths-\(newChat.id.uuidString)")
        
        ContactManager.shared.requestAccess { granted in
            guard granted else {
                print("❌ Access to contacts denied.")
                return
            }
            
            let imported = ContactManager.shared.fetchContacts()
            self.contacts.append(contentsOf: imported)
            self.saveContacts()
        }
    }
    
    private func importContacts() {
        ContactManager.shared.requestAccess { granted in
            guard granted else {
                print("❌ Access to contacts denied.")
                return
            }
            
            let imported = ContactManager.shared.fetchContacts()
            self.contacts = imported
            self.saveContacts()
            hasImportedContacts = true
        }
    }

    private func saveInitialMessageForChatIfNeeded(_ chat: Chat) {
        let key = "savedMessages-\(chat.id.uuidString)"
        guard UserDefaults.standard.data(forKey: key) == nil else { return }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampString = isoFormatter.string(from: Date())

        let message = Message(
            realText: chat.realMessage,
            coverText: chat.coverMessage,
            isSentByCurrentUser: false,
            timestamp: timestampString
        )

        if let encoded = try? JSONEncoder().encode([message]) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    private func getAvailablePathsForContact(_ chat: Chat) -> [String] {
        let key = "availablePaths-\(chat.id.uuidString)"
        if let data = UserDefaults.standard.array(forKey: key) as? [String] {
            return data
        }

        // Return empty array if no paths have been determined
        // The contact detail view will show "unknown" state and allow user to check
        print("⚠️ No cached paths for \(chat.name) - user should check contact's path sharing")
        return [] // Return empty instead of defaulting to ["Email"]
    }
    
    private func updatePathsForContact(_ chat: Chat) {
        guard let email = chat.email else {
            print("⚠️ Cannot update paths - no email for contact")
            return
        }
        
        fetchRecipientPathConfiguration(email: email) { paths in
            DispatchQueue.main.async {
                let key = "availablePaths-\(chat.id.uuidString)"
                UserDefaults.standard.set(paths, forKey: key)
                
                print("🔄 Updated cached paths for \(chat.name): \(paths)")
                
                if paths.isEmpty {
                    print("🔒 \(chat.name) has no available paths")
                }
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

    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }
    
    private func updateChatPreview(for chat: Chat, with message: Message, at index: Int? = nil) {
        let chatIndex = index ?? chats.firstIndex(where: { $0.id == chat.id }) ?? -1
        guard chatIndex >= 0 && chatIndex < chats.count else {
            print("❌ Invalid chat index for preview update")
            return
        }
        
        updateChatPreviewAtIndex(chatIndex, with: message)
        refreshToggle.toggle()
    }

    private func updateChatsWithLatestMessages() {
        updateAllChatPreviews()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
}

enum BadgeSize {
    case small, medium, large
    
    var font: Font {
        switch self {
        case .small: return .caption2
        case .medium: return .caption
        case .large: return .body
        }
    }
    
    var padding: (horizontal: CGFloat, vertical: CGFloat) {
        switch self {
        case .small: return (4, 2)
        case .medium: return (8, 4)
        case .large: return (12, 6)
        }
    }
}

struct PathBadge: View {
    let path: String
    let size: BadgeSize
    
    var pathColor: Color {
        switch path.lowercased() {
        case "sms": return .green
        case "email": return .blue
        default: return .gray
        }
    }
    
    var pathIcon: String {
        switch path.lowercased() {
        case "sms": return "message.fill"
        case "email": return "envelope.fill"
        case "windtexter": return "wind"
        default: return "questionmark"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pathIcon)
                .font(size.font)
            Text(path)
                .font(size.font)
                .fontWeight(.medium)
        }
        .padding(.horizontal, size.padding.horizontal)
        .padding(.vertical, size.padding.vertical)
        .background(pathColor.opacity(0.2))
        .foregroundColor(pathColor)
        .cornerRadius(8)
    }
}

// CRITICAL FIX: Updated ChatRow to show unread counter properly
struct ChatRow: View {
    let chat: Chat
    let searchQuery: String
    let showRealMessage: Bool
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("selectedPathForChat") private var selectedPathForChatRaw: String = ""

    private func shouldShowRealMessageForThisChat() -> Bool {
        let chatModeSettings = (try? JSONDecoder().decode([UUID: String].self, from: selectedPathForChatRaw.data(using: .utf8) ?? Data())) ?? [:]
        let chatIsInCoverMode = chatModeSettings[chat.id] != nil
        return !chatIsInCoverMode  // FIXED: If chat is in cover mode, show cover (false), if not in cover mode, show real (true)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            Circle()
                .fill(Color.gray)
                .frame(width: 50, height: 50)
                .overlay(Text(String(chat.name.prefix(1))).foregroundColor(.white))

            // Chat content with proper truncation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1) // Ensure single line
                        .truncationMode(.tail) // Add ellipsis at the end
                        .frame(maxWidth: .infinity, alignment: .leading) // Take available space
                    
                    Spacer(minLength: 8) // Ensure minimum spacing
                }

                Text(chat.displayMessage(showRealMessage: shouldShowRealMessageForThisChat()))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail) // Also truncate message preview
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading) // Ensure content takes available space

            // Right side info (time and unread count)
            VStack(alignment: .trailing, spacing: 4) {
                Text(chat.time)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // CRITICAL FIX: Always show unread counter when count > 0
                Group {
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .scaleEffect(chat.unreadCount > 0 ? 1.0 : 0.1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: chat.unreadCount)
                    } else {
                        // Invisible placeholder to maintain layout
                        Text("")
                            .font(.caption2)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.clear)
                    }
                }
            }
            .frame(width: 60) // Fixed width for consistent layout
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // FIX: Ensure entire row is tappable
    }
}

// CRITICAL FIX: Updated Chat struct with proper unreadCount handling
struct Chat: Identifiable {
    let id = UUID()
    let name: String
    var realMessage: String
    var coverMessage: String
    var time: String
    var unreadCount: Int  // Make this mutable
    var isFavorite: Bool
    let isNew: Bool
    var phoneNumber: String?
    var email: String?

    init(
        name: String,
        realMessage: String,
        coverMessage: String,
        time: String,
        unreadCount: Int,
        isFavorite: Bool,
        isNew: Bool,
        phoneNumber: String? = nil,
        email: String? = nil
    ) {
        self.name = name
        self.realMessage = realMessage
        self.coverMessage = coverMessage
        self.time = time
        self.unreadCount = unreadCount
        self.isFavorite = isFavorite
        self.isNew = isNew
        self.phoneNumber = phoneNumber
        self.email = email
        
        print("🏗️ Created chat '\(name)' with unreadCount: \(unreadCount)")
    }

    func displayMessage(showRealMessage: Bool) -> String {
        let message = showRealMessage ? realMessage : coverMessage
        return message
    }
}

struct Contact: Identifiable, Codable {
    let id: UUID
    var name: String
    var phoneNumber: String?
    var email: String?
    
    init(name: String, phoneNumber: String? = nil, email: String? = nil) {
        self.id = UUID()
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
    }
}

struct ContactsListView: View {
    @State private var contacts: [Contact] = []
    @State private var showAddContact = false

    var body: some View {
        NavigationView {
            List(contacts) { contact in
                VStack(alignment: .leading) {
                    Text(contact.name).font(.headline)
                    if let phone = contact.phoneNumber {
                        Text("📞 \(phone)").font(.subheadline)
                    }
                    if let email = contact.email {
                        Text("✉️ \(email)").font(.subheadline)
                    }
                }
            }
            .navigationTitle("Contacts")
            .toolbar {
                Button(action: { showAddContact = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(PlainButtonStyle()) // FIX: Explicit button style
                .contentShape(Rectangle()) // FIX: Ensure tappable area
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView { newContact in
                    contacts.append(newContact)
                    saveContacts()
                }
            }
            .onAppear {
                loadContacts()
            }
        }
    }

    func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }

    func loadContacts() {
        if let data = UserDefaults.standard.data(forKey: "savedContacts"),
           let decoded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = decoded
        }
    }
}

// FIX: Updated FilterButton with user activity tracking
struct FilterButton: View {
    let title: String
    @Binding var selectedFilter: String
    @Binding var lastUserActiveTime: Date
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedFilter = title
                lastUserActiveTime = Date() // Track user activity
            }
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(selectedFilter == title ? .bold : .regular)
                .foregroundColor(selectedFilter == title ? .blue : textColor)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle()) // FIX: Explicit button style for better responsiveness
        .contentShape(Rectangle()) // FIX: Ensure entire area is tappable
        .padding(.horizontal, 4)
    }
    
    private var textColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

func getAvailablePathsForCurrentRegion() -> [String] {
    // FOCUS ONLY ON EMAIL
    return ["Email"]
}

struct SettingsView: View {
    @Binding var isDarkMode: Bool
    @AppStorage("showRealMessage") private var showRealMessage: Bool = true
    @AppStorage("selectedPaths") private var selectedPathsData: Data = Data()
    @AppStorage("gmailAccessToken") private var gmailAccessToken: String = ""
    
    // Compression and encryption settings
    @AppStorage("selectedCompressionMethod") private var selectedCompressionMethod: String = "utf8"
    @AppStorage("selectedEncryptionMethod") private var selectedEncryptionMethod: String = "EAX"
    
    @State private var selectedPathsInternal: Set<String> = []
    @AppStorage("isSignedInToGmail") var isSignedInToGmail = false
    @State private var showingCompressionInfo = false
    @State private var showingEncryptionInfo = false
    
    // Auto-update state for path configuration
    @State private var isUpdatingPaths = false
    @State private var lastUpdateTime: Date?
    
    private let allPaths = ["Email", "SMS"]
    
    // Available compression methods
    private let compressionMethods = [
        CompressionMethod(id: "utf8", name: "UTF-8", description: "No compression, direct encoding"),
        CompressionMethod(id: "lz77", name: "LZ77", description: "Dictionary-based compression"),
        CompressionMethod(id: "huffman", name: "Huffman", description: "Frequency-based compression"),
        CompressionMethod(id: "six_bit", name: "6-Bit", description: "6-bit character encoding"),
        CompressionMethod(id: "seven_bit", name: "7-Bit", description: "7-bit character encoding")
    ]
    
    // Available encryption methods
    private let encryptionMethods = [
        EncryptionMethod(id: "EAX", name: "AES-EAX", description: "Authenticated encryption mode"),
        EncryptionMethod(id: "OFB", name: "AES-OFB", description: "Output feedback mode")
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack {
                        Text("Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .padding(.top)
                    }
                    
                    // Basic Settings Section
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Display")
                        
                        VStack(spacing: 12) {
                            Toggle("Dark Mode", isOn: $isDarkMode)
                                .padding(.horizontal, 20)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Gmail Integration Section
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Account Integration")
                        
                        VStack(spacing: 16) {
                            gmailSection
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Delivery Paths Section (Auto-sharing enabled)
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsSectionHeader(title: "Enabled Delivery Paths")
                        
                        // FIXED: Update the toggle behavior in SettingsView body
                        VStack(spacing: 12) {
                            ForEach(allPaths, id: \.self) { path in
                                Toggle(path, isOn: Binding<Bool>(
                                    get: {
                                        let isEnabled = selectedPathsInternal.contains(path)
                                        print("🔍 Toggle get for \(path): \(isEnabled)")
                                        return isEnabled
                                    },
                                    set: { isOn in
                                        print("🔧 Toggle set for \(path): \(isOn)")
                                        
                                        if isOn {
                                            selectedPathsInternal.insert(path)
                                            print("✅ Added \(path) to selectedPathsInternal: \(selectedPathsInternal)")
                                        } else {
                                            selectedPathsInternal.remove(path)
                                            print("🗑️ Removed \(path) from selectedPathsInternal: \(selectedPathsInternal)")
                                        }
                                        
                                        // Save to UserDefaults immediately
                                        if let encoded = try? JSONEncoder().encode(selectedPathsInternal) {
                                            selectedPathsData = encoded
                                            print("💾 Saved to UserDefaults: \(selectedPathsInternal)")
                                        }
                                        
                                        // FIXED: Always attempt to update server, even for empty arrays
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            updateMyPathConfiguration()
                                        }
                                    }
                                ))
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // Compression Method Selection
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SettingsSectionHeader(title: "Compression Method")
                            
                            Button(action: {
                                showingCompressionInfo = true
                            }) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                        }
                        
                        VStack(spacing: 12) {
                            ForEach(compressionMethods, id: \.id) { method in
                                CompressionMethodRow(
                                    method: method,
                                    isSelected: selectedCompressionMethod == method.id,
                                    onSelect: {
                                        selectedCompressionMethod = method.id
                                    }
                                )
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Encryption Method Selection
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            SettingsSectionHeader(title: "Encryption Method")
                            
                            Button(action: {
                                showingEncryptionInfo = true
                            }) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                        }
                        
                        VStack(spacing: 12) {
                            ForEach(encryptionMethods, id: \.id) { method in
                                EncryptionMethodRow(
                                    method: method,
                                    isSelected: selectedEncryptionMethod == method.id,
                                    onSelect: {
                                        selectedEncryptionMethod = method.id
                                    }
                                )
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .onAppear {
            // Load selected paths from UserDefaults
            if let decoded = try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData) {
                selectedPathsInternal = decoded
            } else {
                selectedPathsInternal = Set(allPaths)
            }
            
            isSignedInToGmail = !gmailAccessToken.isEmpty
            
            // Load last update time from UserDefaults
            if let lastUpdate = UserDefaults.standard.object(forKey: "lastPathConfigUpdate") as? Date {
                lastUpdateTime = lastUpdate
            }
            
            // Auto-update paths on app start if user has any enabled
            if !selectedPathsInternal.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    updateMyPathConfiguration()
                }
            }
        }
        .sheet(isPresented: $showingCompressionInfo) {
            CompressionInfoSheet()
        }
        .sheet(isPresented: $showingEncryptionInfo) {
            EncryptionInfoSheet()
        }
        .background(Color(UIColor.systemBackground))
    }
    
    var gmailSection: some View {
        VStack(spacing: 12) {
            Text("Gmail Integration")
                .font(.headline)
            
            if isSignedInToGmail {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connected to Gmail")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    Spacer()
                }
                
                Button("Sign Out") {
                    AuthManager.shared.signOut()
                    isSignedInToGmail = false
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(10)
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            } else {
                Button("Connect Gmail") {
                    signInWithGoogle()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
        }
    }
    
    private func normalizeDeliveryPath(_ path: String) -> String {
        let pathLower = path.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let pathMap: [String: String] = [
            "send_email": "email",
            "send_sms": "sms",
        ]
        
        return pathMap[pathLower] ?? pathLower
    }
    
    private func formatUpdateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func signInWithGoogle() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            print("❌ No root view controller found")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
        ) { result, error in
            if let error = error {
                print("❌ Google Sign-In failed:", error.localizedDescription)
                return
            }
            
            guard let user = result?.user else {
                print("❌ No user object")
                return
            }
            
            let token = user.accessToken.tokenString
            gmailAccessToken = token
            isSignedInToGmail = true
            UserDefaults.standard.set(true, forKey: "isSignedInToGmail")
            UserDefaults.standard.set(token, forKey: "gmailAccessToken")
            UserDefaults.standard.synchronize()
            print("✅ Google Sign-In successful. Token saved.")
        }
    }
    
    // FIXED: Smart path update function in SettingsView
    // FIXED: Smart path update function in SettingsView
    private func updateMyPathConfiguration() {
        guard let currentUserEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email else {
            print("⚠️ Cannot update path config - no user email")
            return
        }
        
        isUpdatingPaths = true
        
        // Normalize paths
        let normalizedPaths = Array(selectedPathsInternal).compactMap { path in
            let normalized = normalizeDeliveryPath(path)
            return normalized.isEmpty ? nil : normalized
        }
        
        print("🔧 Sending paths to server: \(normalizedPaths)")
        
        // Choose endpoint based on whether paths are empty
        let endpoint = normalizedPaths.isEmpty ? "/disable_user_paths" : "/update_user_path_config"
        
        guard let url = URL(string: "\(API.baseURL)\(endpoint)") else {
            print("❌ Invalid URL for \(endpoint)")
            isUpdatingPaths = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any]
        if normalizedPaths.isEmpty {
            // Use disable endpoint
            body = [
                "email": currentUserEmail.lowercased(),
                "device_id": DeviceIDManager.shared.deviceID
            ]
        } else {
            // Use update endpoint
            body = [
                "email": currentUserEmail.lowercased(),
                "enabled_paths": normalizedPaths,
                "device_id": DeviceIDManager.shared.deviceID
            ]
        }
        
        print("📤 Using endpoint: \(endpoint)")
        print("📤 Request body: \(body)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("❌ Failed to serialize JSON: \(error)")
            isUpdatingPaths = false
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isUpdatingPaths = false
                
                if let error = error {
                    print("❌ Network error: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Response status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 200 {
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("✅ Server response: \(json)")
                            
                            let status = json["status"] as? String
                            if status == "updated" || status == "disabled" {
                                self.lastUpdateTime = Date()
                                UserDefaults.standard.set(Date(), forKey: "lastPathConfigUpdate")
                                print("✅ Successfully updated path configuration")
                            }
                        }
                    } else {
                        print("❌ HTTP error: \(httpResponse.statusCode)")
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            print("❌ Error response: \(responseString)")
                        }
                    }
                }
            }
        }.resume()
    }
}
// MARK: - Supporting Data Structures

struct CompressionMethod {
    let id: String
    let name: String
    let description: String
}

struct EncryptionMethod {
    let id: String
    let name: String
    let description: String
}

// MARK: - Custom Views

struct SettingsSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
    }
}

struct CompressionMethodRow: View {
    let method: CompressionMethod
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(method.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

struct EncryptionMethodRow: View {
    let method: EncryptionMethod
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(method.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
    }
}

// MARK: - Info Sheets

struct CompressionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About Compression Methods")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Compression methods reduce the size of your messages before encryption. Both you and the recipient must use the same compression method for messages to be properly decoded.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        InfoCard(
                            title: "UTF-8 (No Compression)",
                            description: "Direct encoding without compression. Best for short messages or when compatibility is most important.",
                            pros: ["Fastest processing", "Universal compatibility"],
                            cons: ["Larger message size"]
                        )
                        
                        InfoCard(
                            title: "LZ77",
                            description: "Dictionary-based compression that finds repeating patterns in text.",
                            pros: ["Good for repetitive text", "Moderate compression"],
                            cons: ["Slower processing"]
                        )
                        
                        InfoCard(
                            title: "Huffman",
                            description: "Frequency-based compression that assigns shorter codes to common characters.",
                            pros: ["Excellent for text", "Good compression ratio"],
                            cons: ["Variable performance"]
                        )
                        
                        InfoCard(
                            title: "6-Bit Encoding",
                            description: "Optimized encoding for common characters using 6 bits per character.",
                            pros: ["Compact for basic text", "Fast processing"],
                            cons: ["Limited character set"]
                        )
                        
                        InfoCard(
                            title: "7-Bit Encoding",
                            description: "Standard ASCII encoding using 7 bits per character.",
                            pros: ["Good balance", "Wide compatibility"],
                            cons: ["ASCII characters only"]
                        )
                    }
                    
                    ImportantNotice(
                        title: "Important",
                        message: "Both users must select the same compression method for messages to be properly decoded. Changing this setting will only affect new messages."
                    )
                }
                .padding()
            }
            .navigationTitle("Compression")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                }
            }
        }
    }
}

struct EncryptionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About Encryption Methods")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Encryption methods secure your messages using AES encryption. Both you and the recipient must use the same encryption method for secure communication.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        InfoCard(
                            title: "AES-EAX",
                            description: "Authenticated encryption mode that provides both confidentiality and integrity protection.",
                            pros: ["Built-in authentication", "Detects tampering", "Secure against most attacks"],
                            cons: ["Slightly larger overhead"]
                        )
                        
                        InfoCard(
                            title: "AES-OFB",
                            description: "Output Feedback mode that turns AES into a stream cipher.",
                            pros: ["Fast encryption", "Error propagation resistance"],
                            cons: ["Requires separate authentication", "IV must be unique"]
                        )
                    }
                    
                    ImportantNotice(
                        title: "Security Notice",
                        message: "Both users must select the same encryption method and share encryption keys securely. AES-EAX is recommended for most users as it provides built-in message authentication."
                    )
                }
                .padding()
            }
            .navigationTitle("Encryption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                }
            }
        }
    }
}

struct InfoCard: View {
    let title: String
    let description: String
    let pros: [String]
    let cons: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Pros", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                    
                    ForEach(pros, id: \.self) { pro in
                        Text("• \(pro)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("Cons", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                    
                    ForEach(cons, id: \.self) { con in
                        Text("• \(con)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ImportantNotice: View {
    let title: String
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

extension HomeView {
    
    // Add this function to normalize paths consistently
    private func normalizeDeliveryPath(_ path: String) -> String {
        let pathLower = path.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let pathMap: [String: String] = [
            "send_email": "email",
            "send_sms": "sms",
        ]
        
        return pathMap[pathLower] ?? pathLower
    }
}
