import SwiftUI

struct SettingsView: View {
    @ObservedObject var appData: AppData
    @State private var showingRoomCodeSheet = false
    @State private var newRoomCode = ""
    @State private var showingConfirmation = false
    @State private var showingShareSheet = false
    @State private var selectedUser: User?
    @State private var showingEditNameSheet = false
    @State private var editedName = ""
    
    var body: some View {
        List {
            if appData.currentUser?.isAdmin ?? false {
                NavigationLink(destination: EditPlanView(appData: appData)) {
                    Text("Edit Plan")
                        .font(.headline)
                }
            }
            NavigationLink(destination: RemindersView(appData: appData)) {
                Text("Reminders")
                    .font(.headline)
            }
            NavigationLink(destination: TreatmentFoodTimerView(appData: appData)) {
                Text("Treatment Food Timer")
                    .font(.headline)
            }
            if appData.currentUser?.isAdmin ?? false {
                NavigationLink(destination: EditUnitsView(appData: appData)) {
                    Text("Edit Units")
                        .font(.headline)
                }
                NavigationLink(destination: EditGroupedItemsView(appData: appData, cycleId: appData.currentCycleId() ?? UUID())) {
                    Text("Edit Grouped Items")
                        .font(.headline)
                }
            }
            NavigationLink(destination: HistoryView(appData: appData)) {
                Text("History")
                    .font(.headline)
            }
            NavigationLink(destination: ContactTIPsView()) {
                Text("Contact TIPs")
                    .font(.headline)
            }
            Section(header: Text("Room Code")) {
                Text("Current Room Code: \(appData.roomCode ?? "None")")
                    .contextMenu {
                        Button("Copy to Clipboard") {
                            UIPasteboard.general.string = appData.roomCode
                        }
                    }
                Button("Change Room Code") {
                    newRoomCode = appData.roomCode ?? ""
                    showingRoomCodeSheet = true
                }
                if appData.currentUser?.isAdmin ?? false {
                    Button("Generate New Room Code") {
                        newRoomCode = UUID().uuidString
                        showingConfirmation = true
                    }
                    Button("Share Room Code") {
                        showingShareSheet = true
                    }
                }
            }
            if appData.currentUser?.isAdmin ?? false {
                Section(header: Text("User Management")) {
                    ForEach(appData.users) { user in
                        HStack {
                            Text(user.name)
                            Spacer()
                            Text(user.isAdmin ? "Admin" : "Log-Only")
                            if user.id == appData.currentUser?.id {
                                Button(action: {
                                    editedName = user.name
                                    showingEditNameSheet = true
                                }) {
                                    Text("Edit Name")
                                }
                            } else {
                                Button(action: {
                                    selectedUser = user
                                }) {
                                    Text("Edit Role")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingRoomCodeSheet) {
            NavigationView {
                Form {
                    TextField("Room Code", text: $newRoomCode)
                }
                .navigationTitle("Enter Room Code")
                .navigationBarItems(
                    leading: Button("Cancel") { showingRoomCodeSheet = false },
                    trailing: Button("Save") {
                        appData.roomCode = newRoomCode
                        if let currentUser = appData.currentUser {
                            let updatedUser = User(id: currentUser.id, name: currentUser.name, isAdmin: currentUser.isAdmin)
                            appData.addUser(updatedUser)
                        }
                        showingRoomCodeSheet = false
                    }
                )
            }
        }
        .alert("Confirm New Room Code", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm") {
                appData.roomCode = newRoomCode
                if let currentUser = appData.currentUser {
                    let updatedUser = User(id: currentUser.id, name: currentUser.name, isAdmin: currentUser.isAdmin)
                    appData.addUser(updatedUser)
                }
            }
        } message: {
            Text("This will switch to a new data set.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivityViewController(activityItems: [
                """
                Join my TIPs App room: \(appData.roomCode ?? "No code available")
                Download TIPs App: 
                        https://testflight.apple.com/join/W93z4G4W
                Please reply to this message with your email so I can invite you to the app via TestFlight.
                """
            ])
        }
        .sheet(item: $selectedUser) { user in
            NavigationView {
                Form {
                    Text("User: \(user.name)")
                    Toggle("Admin Access", isOn: Binding(
                        get: { user.isAdmin },
                        set: { newValue in
                            let updatedUser = User(id: user.id, name: user.name, isAdmin: newValue)
                            appData.addUser(updatedUser)
                            selectedUser = nil
                        }
                    ))
                }
                .navigationTitle("Edit User Role")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { selectedUser = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditNameSheet) {
            NavigationView {
                Form {
                    TextField("Your Name", text: $editedName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .navigationTitle("Edit Your Name")
                .navigationBarItems(
                    leading: Button("Cancel") { showingEditNameSheet = false },
                    trailing: Button("Save") {
                        if let currentUser = appData.currentUser, !editedName.isEmpty {
                            let updatedUser = User(id: currentUser.id, name: editedName, isAdmin: currentUser.isAdmin)
                            appData.addUser(updatedUser)
                            appData.currentUser = updatedUser
                        }
                        showingEditNameSheet = false
                    }
                    .disabled(editedName.isEmpty)
                )
            }
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContactTIPsView: View {
    var body: some View {
        List {
            Section(header: Text("Contact Information")) {
                HStack {
                    Text("Phone:")
                    Spacer()
                    Link("(562) 490-9900", destination: URL(string: "tel:5624909900")!)
                }
                HStack {
                    Text("Fax:")
                    Spacer()
                    Link("(562) 270-1763", destination: URL(string: "tel:5622701763")!)
                }
                VStack(alignment: .leading) {
                    Text("Emails:")
                    Text("enrollment@foodallergyinstitute.com")
                    Text("info@foodallergyinstitute.com")
                    Text("scheduling@foodallergyinstitute.com")
                    Text("patientbilling@foodallergyinstitute.com")
                }
            }
            Section(header: Text("Links")) {
                VStack(alignment: .leading) {
                    Link("TIPs Connect", destination: URL(string: "https://tipconnect.socalfoodallergy.org/")!)
                    Text("- Report Reactions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- General Information/Resources")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Message with On-Call Team")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Request Forms/Letters/Prescriptions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading) {
                    Link("QURE4U My Care Plan", destination: URL(string: "https://www.web.my-care-plan.com/login")!)
                    Text("- View Upcoming Appointments")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Appointment Reminders")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Sign Documents")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- View Educational Materials")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading) {
                    Link("Athena Portal", destination: URL(string: "https://11920.portal.athenahealth.com/")!)
                    Text("- View Upcoming Appointments")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Discharge Instructions")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("- Receipts of Cash Payments for HSA & FSA")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading) {
                    Link("Netsuite", destination: URL(string: "https://6340501.app.netsuite.com/app/login/secure/privatelogin.nl?c=6340501")!)
                    Text("- TIP Fee Payments")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("  - Schedule Payments and Autopay")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Contact TIPs")
    }
}
