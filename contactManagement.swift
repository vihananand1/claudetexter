// MARK: - Contact Management Views - COMPLETE FIXED VERSION

import SwiftUI
import Contacts

// MARK: - Main Contacts View
struct ContactsView: View {
    @State private var contacts: [Contact] = []
    @State private var showingAddContact = false
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts.sorted { $0.name < $1.name }
        } else {
            return contacts.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                contact.email?.localizedCaseInsensitiveContains(searchText) == true ||
                contact.phoneNumber?.localizedCaseInsensitiveContains(searchText) == true
            }.sorted { $0.name < $1.name }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search bar
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                
                if filteredContacts.isEmpty {
                    EmptyContactsView(showingAddContact: $showingAddContact)
                } else {
                    List {
                        ForEach(filteredContacts) { contact in
                            NavigationLink(destination: ContactDetailView(contact: contact, contacts: $contacts)) {
                                ContactRowView(contact: contact)
                            }
                        }
                        .onDelete(perform: deleteContacts)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddContact = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
                
                if !contacts.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                ModifiedAddContactView { newContact in
                    contacts.append(newContact)
                    saveContacts()
                }
            }
            .onAppear {
                loadContacts()
            }
        }
    }
    
    private func deleteContacts(offsets: IndexSet) {
        contacts.remove(atOffsets: offsets)
        saveContacts()
    }
    
    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }
    
    private func loadContacts() {
        if let data = UserDefaults.standard.data(forKey: "savedContacts"),
           let decoded = try? JSONDecoder().decode([Contact].self, from: data) {
            contacts = decoded
        }
    }
}

// MARK: - Contact Row View - FIXED
struct ContactRowView: View {
    let contact: Contact
    @Environment(\.colorScheme) var colorScheme
    @State private var serverPaths: [String] = []
    @State private var isCheckingServerPaths = false
    @State private var hasCheckedServer = false
    
    // Use server paths if available
    var displayPaths: [String] {
        if hasCheckedServer {
            return serverPaths
        } else {
            return locallyAssumedPaths
        }
    }
    
    // Fallback local logic (only used before server check completes)
    var locallyAssumedPaths: [String] {
        var paths: [String] = []
        if contact.phoneNumber != nil {
            paths.append("SMS")
        }
        if contact.email != nil {
            paths.append("Email")
        }
        return paths
    }
    
    var savedPaths: [String] {
        getSavedPathsForContact(contact)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Contact Avatar
            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(contact.name.prefix(1).uppercased()))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Name
                Text(contact.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Contact methods
                VStack(alignment: .leading, spacing: 2) {
                    if let email = contact.email {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if let phone = contact.phoneNumber {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(phone)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Available paths indicator - FIXED to show server status
            VStack(alignment: .trailing, spacing: 4) {
                if isCheckingServerPaths {
                    Text("Checking...")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .fontWeight(.medium)
                } else if !hasCheckedServer {
                    Text("Unknown")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .fontWeight(.medium)
                } else if serverPaths.isEmpty {
                    Text("Private")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                } else if !savedPaths.isEmpty {
                    Text("Active")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                } else {
                    Text("Available")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                }
                
                HStack(spacing: 4) {
                    if isCheckingServerPaths {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else if !hasCheckedServer {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else if serverPaths.isEmpty {
                        Image(systemName: "lock.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        let pathsToShow = savedPaths.isEmpty ? displayPaths : savedPaths
                        ForEach(pathsToShow.prefix(2), id: \.self) { path in
                            PathBadge(path: path, size: .small)
                        }
                        
                        if pathsToShow.count > 2 {
                            Text("+\(pathsToShow.count - 2)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(width: 80)
        }
        .padding(.vertical, 4)
        .onAppear {
            checkServerPathsIfNeeded()
        }
    }
    
    private func checkServerPathsIfNeeded() {
        if loadCachedServerPaths() {
            return
        }
        checkServerPaths()
    }
    
    private func loadCachedServerPaths() -> Bool {
        let key = "serverPaths-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        let timeKey = "serverPathsTime-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        let responseKey = "serverPathsResponded-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        
        if let cachedPaths = UserDefaults.standard.array(forKey: key) as? [String],
           let cacheTime = UserDefaults.standard.object(forKey: timeKey) as? Date,
           UserDefaults.standard.bool(forKey: responseKey) {
            
            // Use cached data if it's less than 30 minutes old
            if Date().timeIntervalSince(cacheTime) < 1800 {
                self.serverPaths = cachedPaths
                self.hasCheckedServer = true
                return true
            }
        }
        
        return false
    }
    
    private func checkServerPaths() {
        guard let email = contact.email else {
            hasCheckedServer = true
            serverPaths = []
            return
        }
        
        guard !isCheckingServerPaths else { return }
        
        isCheckingServerPaths = true
        
        fetchRecipientPathConfiguration(email: email) { paths in
            DispatchQueue.main.async {
                self.serverPaths = paths
                self.hasCheckedServer = true
                self.isCheckingServerPaths = false
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
        
        let body = ["email": email.lowercased()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let paths = json["enabled_paths"] as? [String] else {
                completion([])
                return
            }
            
            completion(paths)
        }.resume()
    }
    
    private func cacheServerPaths(_ paths: [String]) {
        let key = "serverPaths-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        UserDefaults.standard.set(paths, forKey: key)
        
        let timeKey = "serverPathsTime-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        UserDefaults.standard.set(Date(), forKey: timeKey)
        
        let responseKey = "serverPathsResponded-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        UserDefaults.standard.set(true, forKey: responseKey)
    }
    
    private func getSavedPathsForContact(_ contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
}

// MARK: - Contact Detail View - SINGLE CLEAN VERSION

struct ContactDetailView: View {
    let contact: Contact
    @Binding var contacts: [Contact]
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var serverPaths: [String] = []
    @State private var isLoadingServerPaths = false
    @State private var lastServerCheck: Date?
    @State private var hasServerResponded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // CRITICAL FIX: These should NOT be shown as "active" - they're just local assumptions
    var locallyAssumedPaths: [String] {
        var paths: [String] = []
        if contact.phoneNumber != nil {
            paths.append("SMS")
        }
        if contact.email != nil {
            paths.append("Email")
        }
        paths.append("WindTexter")
        return paths
    }
    
    var savedPaths: [String] {
        getSavedPathsForContact(contact)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section remains the same...
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Text(String(contact.name.prefix(1).uppercased()))
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                    
                    Text(contact.name)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top)
                
                // Contact Information section remains the same...
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Contact Information")
                    
                    VStack(spacing: 12) {
                        if let email = contact.email {
                            ContactInfoRow(
                                icon: "envelope.fill",
                                title: "Email",
                                value: email,
                                color: .blue
                            )
                        }
                        
                        if let phone = contact.phoneNumber {
                            ContactInfoRow(
                                icon: "phone.fill",
                                title: "Phone",
                                value: phone,
                                color: .green
                            )
                        }
                        
                        if contact.email == nil && contact.phoneNumber == nil {
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
                
                // FIXED: Server-Based Path Configuration Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionHeader(title: "Recipient's Path Sharing")
                        
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
                    
                    // CRITICAL FIX: Proper state handling - only show as "active" if server actually returned paths
                    Group {
                        if isLoadingServerPaths {
                            loadingServerPathsView
                        } else if !hasServerResponded {
                            unknownServerPathsView
                        } else if hasServerResponded && serverPaths.isEmpty {
                            // FIXED: This is the case when server responded but user has sharing OFF
                            privateServerPathsView
                        } else if hasServerResponded && !serverPaths.isEmpty {
                            // FIXED: Only show as "active" when server actually returned paths
                            activeServerPathsView
                        }
                    }
                }
                
                // FIXED: Local Path Analysis (not "active paths")
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Your Local Analysis")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Paths You Could Try")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        
                        Text("Based on contact info, you could attempt these paths (success not guaranteed)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(locallyAssumedPaths, id: \.self) { path in
                                LocalAttemptPathCard(path: path, contact: contact)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // FIXED: Path Compatibility Analysis (only show if we have REAL server data)
                if hasServerResponded && !serverPaths.isEmpty {
                    PathCompatibilityAnalysis(
                        yourPaths: savedPaths,
                        recipientPaths: serverPaths
                    )
                }
                
                // Action buttons remain the same...
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditContactView(contact: contact) { updatedContact in
                if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
                    contacts[index] = updatedContact
                    saveContacts()
                }
            }
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteContact()
            }
        } message: {
            Text("Are you sure you want to delete \(contact.name)? This action cannot be undone.")
        }
        .onAppear {
            checkServerPaths()
        }
    }
    
    // MARK: - Server Path State Views
    
    private var loadingServerPathsView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Checking recipient's path settings...")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var unknownServerPathsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 30))
                .foregroundColor(.gray)
            
            Text("Path sharing status unknown")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Tap 'Check' to see if this contact shares their path configuration")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // FIXED: This view clearly indicates when sharing is OFF
    private var privateServerPathsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.circle")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            
            Text("Path sharing is disabled")
                .font(.headline)
                .foregroundColor(.orange)
                .fontWeight(.medium)
            
            Text("This contact has not enabled path sharing. You can still try sending messages, but delivery paths are not confirmed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let lastCheck = lastServerCheck {
                Text("Checked: \(formatCheckTime(lastCheck))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // FIXED: Only show this when server actually returned paths
    private var activeServerPathsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Shared Enabled Paths")
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
            
            Text("This contact has shared these enabled delivery paths:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(serverPaths, id: \.self) { path in
                    ServerActivePathCard(path: path, contact: contact)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    // Rest of the methods remain the same...
    private func checkServerPaths() {
        guard let email = contact.email else {
            print("⚠️ Cannot check server paths - no email for contact")
            hasServerResponded = true
            serverPaths = []
            lastServerCheck = Date()
            return
        }
        
        isLoadingServerPaths = true
        hasServerResponded = false
        
        fetchRecipientPathConfiguration(email: email) { paths in
            DispatchQueue.main.async {
                self.serverPaths = paths
                self.hasServerResponded = true
                self.lastServerCheck = Date()
                self.isLoadingServerPaths = false
                
                print("🔍 Server path check complete:")
                print("   Contact: \(self.contact.name)")
                print("   Email: \(email)")
                print("   Server responded: \(self.hasServerResponded)")
                print("   Server returned paths: \(paths)")
                print("   Sharing enabled: \(!paths.isEmpty)")
                
                self.cacheServerPaths(paths)
            }
        }
    }
    
    private func fetchRecipientPathConfiguration(email: String, completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "\(API.baseURL)/get_user_path_config") else {
            print("❌ Invalid API URL")
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email.lowercased()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("📡 Fetching path config for: \(email)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("❌ No data received")
                completion([])
                return
            }
            
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("📡 Raw server response: \(rawResponse)")
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📡 Parsed response: \(json)")
                    
                    if let paths = json["enabled_paths"] as? [String] {
                        print("✅ Server returned paths: \(paths)")
                        print("   Sharing is: \(paths.isEmpty ? "DISABLED" : "ENABLED")")
                        completion(paths)
                    } else {
                        print("⚠️ No enabled_paths key found")
                        completion([])
                    }
                } else {
                    print("❌ Failed to parse JSON")
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
        
        let responseKey = "serverPathsResponded-\(contact.email ?? contact.phoneNumber ?? "unknown")"
        UserDefaults.standard.set(true, forKey: responseKey)
    }
    
    private func formatCheckTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getSavedPathsForContact(_ contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    
    private func deleteContact() {
        contacts.removeAll { $0.id == contact.id }
        saveContacts()
        dismiss()
    }
    
    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "savedContacts")
        }
    }
}

// FIXED: New card type for "paths you could try" (not active paths)
struct LocalAttemptPathCard: View {
    let path: String
    let contact: Contact
    
    var canAttempt: Bool {
        switch path.lowercased() {
        case "sms": return contact.phoneNumber != nil
        case "email": return contact.email != nil
        case "windtexter": return true
        default: return false
        }
    }
    
    var pathDescription: String {
        if canAttempt {
            switch path.lowercased() {
            case "sms": return "Can attempt SMS"
            case "email": return "Can attempt email"
            case "windtexter": return "Can try direct messaging"
            default: return "Could try this path"
            }
        } else {
            switch path.lowercased() {
            case "sms": return "No phone number"
            case "email": return "No email address"
            default: return "Missing contact info"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: canAttempt ? "questionmark.circle" : "xmark.circle")
                    .foregroundColor(canAttempt ? .orange : .red)
                    .font(.caption)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(canAttempt ? Color.orange.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Edit Contact View
struct EditContactView: View {
    let contact: Contact
    let onSave: (Contact) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ModifiedAddContactView(
            existingContact: contact,
            onSave: { updatedContact in
                onSave(updatedContact)
                dismiss()
            },
            onCancel: {
                dismiss()
            }
        )
    }
}

// MARK: - Modified AddContactView for editing
struct ModifiedAddContactView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let existingContact: Contact?
    let onSave: (Contact) -> Void
    let onCancel: (() -> Void)?
    
    @State private var availablePaths: [String] = []
    @State private var isChecking: Bool = false
    @State private var name: String
    @State private var phoneNumber: String
    @State private var email: String
    @State private var selectedRegionCode: String
    
    init(existingContact: Contact? = nil, onSave: @escaping (Contact) -> Void, onCancel: (() -> Void)? = nil) {
        self.existingContact = existingContact
        self.onSave = onSave
        self.onCancel = onCancel
        
        _name = State(initialValue: existingContact?.name ?? "")
        _email = State(initialValue: existingContact?.email ?? "")
        
        let phoneWithoutCode = existingContact?.phoneNumber?.replacingOccurrences(of: "^\\+\\d+", with: "", options: .regularExpression) ?? ""
        _phoneNumber = State(initialValue: phoneWithoutCode)
        
        let detectedRegion = existingContact?.phoneNumber != nil ?
            ModifiedAddContactView.detectRegionFromPhone(existingContact!.phoneNumber!) :
            countries.first!.regionCode
        _selectedRegionCode = State(initialValue: detectedRegion)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Contact Info")) {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        
                    Picker("Country Code", selection: $selectedRegionCode) {
                        ForEach(countries) { country in
                            let label = "\(country.name) (\(country.code))"
                            Text(label).tag(country.regionCode)
                        }
                    }
                    
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                }

                Section(header: Text("Available Delivery Paths")) {
                    if isChecking {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking available paths...")
                                .foregroundColor(.gray)
                        }
                    } else if availablePaths.isEmpty {
                        Text("No paths available")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(availablePaths, id: \.self) { path in
                            HStack {
                                PathBadge(path: path, size: .small)
                                
                                Text(getPathDescription(path))
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                
                if let contact = existingContact {
                    Section(header: Text("Currently Saved Paths")) {
                        let currentPaths = getCurrentlySavedPaths(for: contact)
                        if currentPaths.isEmpty {
                            Text("No paths previously configured")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(currentPaths, id: \.self) { path in
                                HStack {
                                    PathBadge(path: path, size: .small)
                                    Text("Previously configured")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingContact == nil ? "Add Contact" : "Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContact()
                    }
                    .disabled(name.isEmpty || (phoneNumber.isEmpty && email.isEmpty))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let onCancel = onCancel {
                            onCancel()
                        } else {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
            .onChange(of: phoneNumber) { _ in checkPaths() }
            .onChange(of: email) { _ in checkPaths() }
            .onChange(of: selectedRegionCode) { _ in checkPaths() }
            .onAppear {
                if existingContact != nil {
                    checkPaths()
                }
            }
        }
    }
    
    private func saveContact() {
        let country = countries.first(where: { $0.regionCode == selectedRegionCode }) ?? countries[0]
        let fullNumber = phoneNumber.isEmpty ? nil : (country.code + phoneNumber)
        
        let contact = Contact(
            name: name,
            phoneNumber: fullNumber,
            email: email.isEmpty ? nil : email
        )

        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        UserDefaults.standard.set(availablePaths, forKey: key)

        onSave(contact)
        
        if onCancel == nil {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func checkPaths() {
        guard !phoneNumber.isEmpty || !email.isEmpty else {
            availablePaths = []
            return
        }

        let country = countries.first(where: { $0.regionCode == selectedRegionCode }) ?? countries[0]
        let fullNumber = phoneNumber.isEmpty ? nil : (country.code + phoneNumber)
        let contact = Contact(
            name: name,
            phoneNumber: fullNumber,
            email: email.isEmpty ? nil : email
        )

        isChecking = true
        
        fetchAvailablePaths(for: contact, region: selectedRegionCode) { regionPaths in
            DispatchQueue.main.async {
                self.availablePaths = regionPaths
                self.isChecking = false
            }
        }
    }
    
    private func getUserEnabledPaths() -> Set<String> {
        guard let selectedPathsData = UserDefaults.standard.data(forKey: "selectedPaths"),
              let enabledPaths = try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData) else {
            return Set(getAvailablePathsForCurrentRegion())
        }
        return enabledPaths
    }
    
    private func getPathDescription(_ path: String) -> String {
        switch path.lowercased() {
        case "sms": return "Text messaging"
        case "email", "send_email": return "Email messaging"
        case "windtexter": return "Direct secure channel"
        default: return path
        }
    }
    
    private func getCurrentlySavedPaths(for contact: Contact) -> [String] {
        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
        return (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    
    static func detectRegionFromPhone(_ phoneNumber: String) -> String {
        for country in countries {
            if phoneNumber.hasPrefix(country.code) {
                return country.regionCode
            }
        }
        return countries.first!.regionCode
    }
}

// MARK: - Supporting Views

struct ActivePathCard: View {
    let path: String
    let contact: Contact
    
    var pathDescription: String {
        switch path.lowercased() {
        case "sms": return "Text messaging active"
        case "email", "send_email": return "Email messaging active"
        case "windtexter": return "Secure channel active"
        default: return "Active"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct ServerActivePathCard: View {
    let path: String
    let contact: Contact
    
    var pathDescription: String {
        switch path.lowercased() {
        case "sms": return "Text messaging active"
        case "email": return "Email messaging active"
        case "windtexter": return "Secure channel active"
        default: return "Active"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

struct LocalPathCard: View {
    let path: String
    let contact: Contact
    
    var isLocallyAvailable: Bool {
        switch path.lowercased() {
        case "sms": return contact.phoneNumber != nil
        case "email": return contact.email != nil
        case "windtexter": return true
        default: return false
        }
    }
    
    var pathDescription: String {
        if isLocallyAvailable {
            switch path.lowercased() {
            case "sms": return "You can try SMS"
            case "email": return "You can try email"
            case "windtexter": return "Direct messaging"
            default: return "Locally available"
            }
        } else {
            switch path.lowercased() {
            case "sms": return "No phone number"
            case "email": return "No email address"
            default: return "Not available"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: isLocallyAvailable ? "questionmark.circle" : "xmark.circle")
                    .foregroundColor(isLocallyAvailable ? .orange : .red)
                    .font(.caption)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct PathCompatibilityAnalysis: View {
    let yourPaths: [String]
    let recipientPaths: [String]
    
    var compatiblePaths: [String] {
        return yourPaths.filter { recipientPaths.contains($0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Compatibility Analysis")
            
            if compatiblePaths.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading) {
                        Text("No compatible paths")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                        Text("You and this contact have no shared delivery paths enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("Compatible paths found")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        
                        HStack {
                            ForEach(compatiblePaths, id: \.self) { path in
                                PathBadge(path: path, size: .small)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search contacts...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct EmptyContactsView: View {
    @Binding var showingAddContact: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Contacts Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your first contact to start secure messaging")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showingAddContact = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Contact")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .padding()
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
    }
}

struct ContactInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
            
            Button(action: {
                UIPasteboard.general.string = value
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct PathCard: View {
    let path: String
    let contact: Contact
    
    var isAvailable: Bool {
        switch path.lowercased() {
        case "sms": return contact.phoneNumber != nil
        case "email": return contact.email != nil
        case "windtexter": return true
        default: return false
        }
    }
    
    var pathDescription: String {
        switch path.lowercased() {
        case "sms": return "Send via text message"
        case "email": return "Send via email"
        case "windtexter": return "Direct secure channel"
        default: return ""
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PathBadge(path: path, size: .medium)
                Spacer()
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isAvailable ? .green : .red)
            }
            
            Text(pathDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}
