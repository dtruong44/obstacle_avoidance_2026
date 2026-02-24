import SwiftUI

//
//  Obstacle Avoidance App
//  ContentView.swift
//
//  Last modified: 3/27/2025
//

struct ContentView: View {
    @State private var showAlert = false
    @State private var startPressed = false
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @State private var currentUser: User?
    @AppStorage("username") private var username = ""

    var body: some View {
        VStack {
            TabbedView(user: $currentUser)
        }
        .onAppear {
            Task {
                await getUserInfo()
            }
        }
    }

    private func getUserInfo() async {
        let users = await Database.shared.fetchUsers()
        currentUser = users.first(where: { $0.username == username })
    }
}

// MARK: - Navigation Hierarchy
struct TabbedView: View {
    @Binding var user: User?

    init(user: Binding<User?>) {
        self._user = user
        UITabBar.appearance().backgroundColor = UIColor.lightGray
        UITabBar.appearance().isTranslucent = true
    }

    var body: some View {
        TabView {
            InstructionView()
                .tabItem {
                    Image(systemName: "house.fill").accessibility(label: Text("Home Tab"))
                    Text("Home")
                }

            CameraView()
                .tabItem {
                    Image(systemName: "camera.fill").accessibility(label: Text("Camera Tab"))
                    Text("Camera")
                }

            NavigationStack {
                SettingsView(user: $user)
            }
            .tabItem {
                Image(systemName: "gear").accessibility(label: Text("Settings Tab"))
                Text("Settings")
            }
        }
    }
}

struct SettingsView: View {
    @Binding var user: User?

    var body: some View {
        List {
            NavigationLink(destination: AccountScreen(user: $user)) {
                Label("Account", systemImage: "person.crop.circle")
            }
            NavigationLink(destination: EmergencyContactView(user: user)) {
                Label("Emergency Contacts", systemImage: "phone.circle")
            }
            NavigationLink(destination: PreferencesView()) {
                Label("Preferences", systemImage: "slider.horizontal.3")
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Refactored Preferences (Local Storage)
struct PreferencesView: View {
    // These pull directly from your UserDefaultsHandler
    @State private var hapticFeedback: Bool = UserDefaultsHandler.shared.getHapticFeedback()
    @State private var locationSharing: Bool = UserDefaultsHandler.shared.getLocationSharing()
    @State private var measurementType: String = UserDefaultsHandler.shared.getMeasurementType()
    @State private var userHeight: Double = UserDefaultsHandler.shared.getUserHeight()

    let heightRange = Array(20...80)

    var body: some View {
        List {
            Section(header: Text("Device Calibration")) {
                Picker("Measurement Type", selection: $measurementType) {
                    Text("Feet").tag("Feet")
                    Text("Meters").tag("Meters")
                }
                .onChange(of: measurementType) { newValue in
                    UserDefaultsHandler.shared.setMeasurementType(type: newValue)
                }

                Picker("User Height", selection: $userHeight) {
                    ForEach(heightRange, id: \.self) { height in
                        Text("\(height) \(measurementType == "Feet" ? "in" : "cm")").tag(Double(height))
                    }
                }
                .onChange(of: userHeight) { newValue in
                    UserDefaultsHandler.shared.setUserHeight(height: newValue)
                }
            }

            Section(header: Text("Feedback & Privacy")) {
                Toggle("Receive haptic feedback", isOn: $hapticFeedback)
                    .onChange(of: hapticFeedback) { newValue in
                        UserDefaultsHandler.shared.setHapticFeedback(enabled: newValue)
                    }

                Toggle("Share your location", isOn: $locationSharing)
                    .onChange(of: locationSharing) { newValue in
                        UserDefaultsHandler.shared.setLocationSharing(enabled: newValue)
                    }
            }
        }
        .navigationTitle("Preferences")
    }
}

// MARK: - Account & Emergency (Database Storage)

struct AccountScreen: View {
    @State private var isEditing: Bool = false
    @Binding var user: User?
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    
    @State private var updatedUsername = ""
    @State private var updatedName = ""
    @State private var updatedEmail = ""
    @State private var updatedPhoneNumber = ""
    @State private var updatedAddress = ""

    var body: some View {
        Form {
            Section(header: Text("Account Information")) {
                if let _ = user {
                    editableRow(label: "Username", text: $updatedUsername)
                    editableRow(label: "Name", text: $updatedName)
                    editableRow(label: "Email", text: $updatedEmail, keyboard: .emailAddress)
                    editableRow(label: "Phone Number", text: $updatedPhoneNumber, keyboard: .phonePad)
                    editableRow(label: "Address", text: $updatedAddress)
                    
                    HStack {
                        Text("Password:").fontWeight(.bold)
                        Spacer()
                        Text("********").foregroundColor(.gray)
                    }
                }
            }
            .onAppear {
                if let u = user {
                    updatedUsername = u.username
                    updatedName = u.name
                    updatedEmail = u.email
                    updatedPhoneNumber = u.phoneNumber
                    updatedAddress = u.address
                }
            }

            Button(action: {
                Task {
                    if let userId = user?.id { await deleteAccount(userId: userId) }
                }
            }) {
                Text("Delete Account").foregroundColor(.red).font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Account")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { saveChanges() }
                    isEditing.toggle()
                }
            }
        }
    }

    private func saveChanges() {
        guard let userId = user?.id else { return }
        Task {
            await Database.shared.updateUser(
                userId: userId,
                newName: updatedName,
                newUsername: updatedUsername,
                newPhoneNumber: updatedPhoneNumber,
                newEmail: updatedEmail,
                newAddress: updatedAddress
            )
        }
    }

    private func editableRow(label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text("\(label):").fontWeight(.bold)
            Spacer()
            if isEditing {
                TextField("Enter \(label)", text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(keyboard)
            } else {
                Text(text.wrappedValue).foregroundColor(.gray)
            }
        }
    }

    private func deleteAccount(userId: Int) async {
        await Database.shared.deleteUser(userId: userId)
        isLoggedIn = false
    }
}

struct EmergencyContactView: View {
    let user: User?
    @State private var contacts: [EmergencyContact] = []
    @State private var addingEC = false
    
    @State private var nameEC = ""
    @State private var phoneNumberEC = ""
    @State private var addressEC = ""

    var body: some View {
        VStack {
            List {
                Section(header: Text("Emergency Contacts")) {
                    if contacts.isEmpty {
                        Text("No emergency contacts available.").foregroundColor(.gray)
                    } else {
                        ForEach(contacts, id: \.name) { contact in
                            EmergencyContactCard(contact: contact, onDelete: {
                                Task { await deleteContact(contact) }
                            })
                        }
                    }
                }
                
                if addingEC {
                    VStack {
                        TextField("Name", text: $nameEC)
                        TextField("Phone", text: $phoneNumberEC)
                        TextField("Address", text: $addressEC)
                        Button("Save") { Task { await saveNewContact() } }
                    }
                }
            }
            
            Button("Add Contact") { addingEC.toggle() }
                .padding()
        }
        .onAppear {
            if let userContacts = user?.emergencyContacts { contacts = userContacts }
        }
    }

    private func saveNewContact() async {
        guard let userId = user?.id else { return }
        let new = EmergencyContact(name: nameEC, phoneNumber: phoneNumberEC, address: addressEC)
        await Database.shared.addEmergencyContact(userId: userId, newEC: new)
        contacts.append(new)
        addingEC = false
    }

    private func deleteContact(_ contact: EmergencyContact) async {
        guard let userId = user?.id else { return }
        await Database.shared.deleteEmergencyContact(userId: userId, contactName: contact.name)
        contacts.removeAll { $0.name == contact.name }
    }
}

struct EmergencyContactCard: View {
    let contact: EmergencyContact
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(contact.name).bold()
                Text(contact.phoneNumber).foregroundColor(.blue)
            }
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
        }
    }
}