import SwiftUI

// Represents a country with dialing code and region identifier, used for contact entry.
struct Country: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let code: String // e.g. +1
    let regionCode: String // e.g. US
}

// List of supported countries for contact selection in the UI.
let countries: [Country] = [
    Country(name: "United States", code: "+1", regionCode: "US"),
    Country(name: "United Kingdom", code: "+44", regionCode: "GB"),
    Country(name: "India", code: "+91", regionCode: "IN"),
    Country(name: "Brazil", code: "+55", regionCode: "BR"),
    Country(name: "Germany", code: "+49", regionCode: "DE"),
    Country(name: "China", code: "+86", regionCode: "CN"),
    Country(name: "Other", code: "+0", regionCode: "default")
]

/// SwiftUI view for adding a new contact, including phone, email, and region selection.
struct AddContactView: View {
    @Environment(\.presentationMode) var presentationMode

    @State private var availablePaths: [String] = []
    @State private var isChecking: Bool = false
    @State private var name: String = ""
    @State private var phoneNumber: String = ""
    @State private var email: String = ""
    @State private var selectedRegionCode: String = countries.first!.regionCode

    var onSave: (Contact) -> Void

    var body: some View {
        // Main UI: form for entering contact info and displaying available delivery paths.
        NavigationView {
            Form {
                Section(header: Text("Contact Info")) {
                    TextField("Name", text: $name)
                    Picker("Country Code", selection: $selectedRegionCode) {
                        ForEach(countries) { country in
                            let label = "\(country.name) (\(country.code))"
                            Text(label).tag(country.regionCode)
                        }
                    }
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                Section(header: Text("Available Paths")) {
                    if isChecking {
                        Text("Checking...").foregroundColor(.gray)
                    } else if availablePaths.isEmpty {
                        Text("No paths available").foregroundColor(.gray)
                    } else {
                        ForEach(availablePaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(path)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Contact")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let country = countries.first(where: { $0.regionCode == selectedRegionCode }) ?? countries[0]
                        let fullNumber = country.code + phoneNumber
                        let contact = Contact(
                            name: name,
                            phoneNumber: phoneNumber.isEmpty ? nil : fullNumber,
                            email: email.isEmpty ? nil : email
                        )

                        let key = "availablePaths-\(contact.phoneNumber ?? contact.email ?? "unknown")"
                        UserDefaults.standard.set(availablePaths, forKey: key)

                        onSave(contact)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(name.isEmpty || (phoneNumber.isEmpty && email.isEmpty))
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onChange(of: phoneNumber) { _ in checkPaths() }
            .onChange(of: email) { _ in checkPaths() }
            .onChange(of: selectedRegionCode) { _ in checkPaths() }
        }
    }
    
    private func getUserEnabledPaths() -> Set<String> {
        guard let selectedPathsData = UserDefaults.standard.data(forKey: "selectedPaths"),
              let enabledPaths = try? JSONDecoder().decode(Set<String>.self, from: selectedPathsData) else {
            return Set(getAvailablePathsForCurrentRegion())
        }
        return enabledPaths
    }

    /// Checks available delivery paths for the current input and updates the UI.
    func checkPaths() {
        guard !phoneNumber.isEmpty || !email.isEmpty else {
            availablePaths = []
            return
        }

        let country = countries.first(where: { $0.regionCode == selectedRegionCode }) ?? countries[0]
        let fullNumber = country.code + phoneNumber
        let contact = Contact(
            name: name,
            phoneNumber: phoneNumber.isEmpty ? nil : fullNumber,
            email: email.isEmpty ? nil : email
        )

        isChecking = true
        
        // Get region-based paths - FIXED: Show all server-provided paths
        fetchAvailablePaths(for: contact, region: selectedRegionCode) { regionPaths in
            DispatchQueue.main.async {
                // Show all server-provided paths without filtering by user settings
                self.availablePaths = regionPaths
                self.isChecking = false
                
                print("🔧 Path filtering removed - showing all server paths:")
                print("   Server provided paths: \(regionPaths)")
                
                // Auto-update user settings to include server paths
                if !regionPaths.isEmpty {
                    self.updateUserSettingsWithServerPaths(regionPaths)
                }
            }
        }
    }
    
    // Auto-update user settings based on server response
    private func updateUserSettingsWithServerPaths(_ serverPaths: [String]) {
        var currentSettings = getUserEnabledPaths()
        var updated = false
        
        for path in serverPaths {
            if !currentSettings.contains(path) {
                currentSettings.insert(path)
                updated = true
            }
        }
        
        if updated {
            if let encoded = try? JSONEncoder().encode(currentSettings) {
                UserDefaults.standard.set(encoded, forKey: "selectedPaths")
                print("🔧 Auto-updated user settings to include: \(Array(currentSettings))")
            }
        }
    }
}

/// Makes a network request to fetch available delivery paths for a contact and region.
/// Calls completion with the list of available paths.
func fetchAvailablePaths(for contact: Contact, region: String = "US", completion: @escaping ([String]) -> Void) {
    guard let url = URL(string: "\(API.baseURL)/check_available_paths") else {
        print("❌ Invalid URL")
        completion([])
        return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let normalizedPhone = contact.phoneNumber?.replacingOccurrences(of: "+", with: "")

    let payload: [String: Any] = [
        "phone": normalizedPhone ?? "",
        "email": contact.email ?? "",
        "region": region
    ]

    print("📤 Sending payload:", payload)

    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    URLSession.shared.dataTask(with: req) { data, response, error in
        if let error = error {
            print("❌ Network error:", error.localizedDescription)
            completion([])
            return
        }

        guard let data = data else {
            print("❌ No data returned from server")
            completion([])
            return
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("📨 Raw response:", raw)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("🧾 Parsed JSON:", json)

            if let paths = json["availablePaths"] as? [String] {
                print("✅ Available paths:", paths)
                completion(paths)
            } else {
                print("❌ 'availablePaths' key missing or not an array of strings")
                completion([])
            }
        } else {
            print("❌ Failed to parse JSON")
            completion([])
        }
    }.resume()
}
