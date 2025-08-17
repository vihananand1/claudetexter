import Contacts

/// Manages access to and retrieval of device contacts using the Contacts framework.
/// Singleton pattern for shared access across the app.
class ContactManager {
    static let shared = ContactManager() // Shared instance

    private let store = CNContactStore()

    /// Requests permission to access the user's contacts. Calls completion with result.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// Fetches device contacts and converts them to Contact models for use in the app.
    func fetchContacts() -> [Contact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [Contact] = []

        do {
            try store.enumerateContacts(with: request) { cnContact, _ in
                let name = "\(cnContact.givenName) \(cnContact.familyName)".trimmingCharacters(in: .whitespaces)
                let phone = cnContact.phoneNumbers.first?.value.stringValue
                let email = cnContact.emailAddresses.first?.value as String?

                // Avoid adding contacts with no identifier fields
                guard !name.isEmpty || phone != nil || email != nil else { return }

                result.append(Contact(name: name, phoneNumber: phone, email: email))
            }
        } catch {
            print("❌ Failed to fetch contacts:", error.localizedDescription)
        }

        return result
    }
}
