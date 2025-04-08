import Foundation
import SwiftUI
import FirebaseDatabase

class AppData: ObservableObject {
    @Published var cycles: [Cycle] = []
    @Published var cycleItems: [UUID: [Item]] = [:]
    @Published var groupedItems: [UUID: [GroupedItem]] = [:]
    @Published var units: [Unit] = []
    @Published var consumptionLog: [UUID: [UUID: [LogEntry]]] = [:]
    @Published var lastResetDate: Date?
    @Published var treatmentTimerEnd: Date? {
        didSet {
            setTreatmentTimerEnd(treatmentTimerEnd)
            saveTimerState()
        }
    }
    @Published var users: [User] = []
    @Published var currentUser: User? {
        didSet { saveCurrentUserSettings() }
    }
    @Published var categoryCollapsed: [String: Bool] = [:]
    @Published var groupCollapsed: [UUID: Bool] = [:] // Keyed by group ID
    @Published var roomCode: String? {
        didSet {
            if let roomCode = roomCode {
                UserDefaults.standard.set(roomCode, forKey: "roomCode")
                dbRef = Database.database().reference().child("rooms").child(roomCode)
                loadFromFirebase()
            } else {
                UserDefaults.standard.removeObject(forKey: "roomCode")
                dbRef = nil
            }
        }
    }
    @Published var syncError: String?
    @Published var isLoading: Bool = true
    
    private var pendingConsumptionLogUpdates: [UUID: [UUID: [LogEntry]]] = [:] // Track pending updates
    
    private var dbRef: DatabaseReference?
    private var isAddingCycle = false
    public var treatmentTimerId: String? {
        didSet { saveTimerState() }
    }
    private var lastSaveTime: Date?

    // Functions to handle profile images
    func saveProfileImage(_ image: UIImage, forCycleId cycleId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        let fileName = "profile_\(cycleId.uuidString).jpg"
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName) {
            try? data.write(to: url)
            UserDefaults.standard.set(fileName, forKey: "profileImage_\(cycleId.uuidString)")
        }
    }
    
    func loadProfileImage(forCycleId cycleId: UUID) -> UIImage? {
        guard let fileName = UserDefaults.standard.string(forKey: "profileImage_\(cycleId.uuidString)") else {
            return nil
        }
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        
        return nil
    }
    
    func deleteProfileImage(forCycleId cycleId: UUID) {
        guard let fileName = UserDefaults.standard.string(forKey: "profileImage_\(cycleId.uuidString)") else {
            return
        }
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName) {
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: "profileImage_\(cycleId.uuidString)")
        }
    }

    init() {
        print("AppData initializing")
        logToFile("AppData initializing")
        if let savedRoomCode = UserDefaults.standard.string(forKey: "roomCode") {
            self.roomCode = savedRoomCode
        }
        units = [Unit(name: "mg"), Unit(name: "g")]
        if let userIdStr = UserDefaults.standard.string(forKey: "currentUserId"),
           let userId = UUID(uuidString: userIdStr) {
            loadCurrentUserSettings(userId: userId)
        }
        loadCachedData()
        
        // Ensure all groups start collapsed
        for (cycleId, groups) in groupedItems {
            for group in groups {
                if groupCollapsed[group.id] == nil {
                    groupCollapsed[group.id] = true
                }
            }
        }
        
        loadTimerState()
        checkAndResetIfNeeded()
        rescheduleDailyReminders()
        
        print("AppData init: Loaded treatmentTimerEnd = \(String(describing: treatmentTimerEnd)), treatmentTimerId = \(String(describing: treatmentTimerId))")
        logToFile("AppData init: Loaded treatmentTimerEnd = \(String(describing: treatmentTimerEnd)), treatmentTimerId = \(String(describing: treatmentTimerId))")
        if let endDate = treatmentTimerEnd {
            if endDate > Date() {
                print("AppData init: Active timer found, endDate = \(endDate)")
                logToFile("AppData init: Active timer found, endDate = \(endDate)")
            } else {
                print("AppData init: Timer expired, clearing treatmentTimerEnd")
                logToFile("AppData init: Timer expired, clearing treatmentTimerEnd")
                treatmentTimerEnd = nil
                treatmentTimerId = nil
            }
        } else {
            print("AppData init: No active timer to resume")
            logToFile("AppData init: No active timer to resume")
        }
    }
    
    private func loadCachedData() {
        if let cycleData = UserDefaults.standard.data(forKey: "cachedCycles"),
           let decodedCycles = try? JSONDecoder().decode([Cycle].self, from: cycleData) {
            self.cycles = decodedCycles
        }
        if let itemsData = UserDefaults.standard.data(forKey: "cachedCycleItems"),
           let decodedItems = try? JSONDecoder().decode([UUID: [Item]].self, from: itemsData) {
            self.cycleItems = decodedItems
        }
        if let groupedItemsData = UserDefaults.standard.data(forKey: "cachedGroupedItems"),
           let decodedGroupedItems = try? JSONDecoder().decode([UUID: [GroupedItem]].self, from: groupedItemsData) {
            self.groupedItems = decodedGroupedItems
        }
        if let logData = UserDefaults.standard.data(forKey: "cachedConsumptionLog"),
           let decodedLog = try? JSONDecoder().decode([UUID: [UUID: [LogEntry]]].self, from: logData) {
            self.consumptionLog = decodedLog
        }
    }

    private func saveCachedData() {
        if let cycleData = try? JSONEncoder().encode(cycles) {
            UserDefaults.standard.set(cycleData, forKey: "cachedCycles")
        }
        if let itemsData = try? JSONEncoder().encode(cycleItems) {
            UserDefaults.standard.set(itemsData, forKey: "cachedCycleItems")
        }
        if let groupedItemsData = try? JSONEncoder().encode(groupedItems) {
            UserDefaults.standard.set(groupedItemsData, forKey: "cachedGroupedItems")
        }
        if let logData = try? JSONEncoder().encode(consumptionLog) {
            UserDefaults.standard.set(logData, forKey: "cachedConsumptionLog")
        }
        UserDefaults.standard.synchronize()
    }

    private func loadTimerState() {
        guard let url = timerStateURL() else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let state = try JSONDecoder().decode(TimerState.self, from: data)
                self.treatmentTimerEnd = state.endDate
                self.treatmentTimerId = state.timerId
                print("Loaded timer state: endDate = \(String(describing: treatmentTimerEnd)), timerId = \(String(describing: treatmentTimerId))")
                logToFile("Loaded timer state: endDate = \(String(describing: treatmentTimerEnd)), timerId = \(String(describing: treatmentTimerId))")
            } else {
                print("No timer state file found at \(url.path)")
                logToFile("No timer state file found at \(url.path)")
            }
        } catch {
            print("Failed to load timer state: \(error)")
            logToFile("Failed to load timer state: \(error)")
        }
    }

    public func saveTimerState() {
        guard let url = timerStateURL() else { return }
        
        let now = Date()
        if let last = lastSaveTime, now.timeIntervalSince(last) < 0.5 {
            print("Debounced saveTimerState: too soon since last save at \(last)")
            logToFile("Debounced saveTimerState: too soon since last save at \(last)")
            return
        }
        
        do {
            let state = TimerState(endDate: treatmentTimerEnd, timerId: treatmentTimerId)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
            lastSaveTime = now
            print("Saved timer state: endDate = \(String(describing: treatmentTimerEnd)), timerId = \(String(describing: treatmentTimerId)) to \(url.path)")
            logToFile("Saved timer state: endDate = \(String(describing: treatmentTimerEnd)), timerId = \(String(describing: treatmentTimerId)) to \(url.path)")
        } catch {
            print("Failed to save timer state: \(error)")
            logToFile("Failed to save timer state: \(error)")
        }
    }

    private func timerStateURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("timer_state.json")
    }

    func logToFile(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("app_log.txt")
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? logEntry.data(using: .utf8)?.write(to: fileURL)
            }
        }
    }

    private func loadCurrentUserSettings(userId: UUID) {
        if let data = UserDefaults.standard.data(forKey: "userSettings_\(userId.uuidString)"),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            self.currentUser = user
            print("Loaded current user \(userId)")
            logToFile("Loaded current user \(userId)")
        }
    }

    private func saveCurrentUserSettings() {
        guard let user = currentUser else { return }
        UserDefaults.standard.set(user.id.uuidString, forKey: "currentUserId")
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "userSettings_\(user.id.uuidString)")
        }
        saveCachedData()
    }

    private func loadFromFirebase() {
        guard let dbRef = dbRef else {
            print("No database reference available.")
            logToFile("No database reference available.")
            syncError = "No room code set."
            self.isLoading = false
            return
        }
        
        dbRef.child("cycles").observe(.value) { snapshot in
            if self.isAddingCycle { return }
            var newCycles: [Cycle] = []
            var newCycleItems: [UUID: [Item]] = self.cycleItems
            var newGroupedItems: [UUID: [GroupedItem]] = self.groupedItems
            
            print("Firebase snapshot received: \(snapshot)")
            self.logToFile("Firebase snapshot received: \(snapshot)")
            
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                for (key, dict) in value {
                    var mutableDict = dict
                    mutableDict["id"] = key
                    guard let cycle = Cycle(dictionary: mutableDict) else { continue }
                    newCycles.append(cycle)
                    
                    if let itemsDict = dict["items"] as? [String: [String: Any]], !itemsDict.isEmpty {
                        let firebaseItems = itemsDict.compactMap { (itemKey, itemDict) -> Item? in
                            var mutableItemDict = itemDict
                            mutableItemDict["id"] = itemKey
                            return Item(dictionary: mutableItemDict)
                        }.sorted { $0.order < $1.order }
                        
                        if let localItems = newCycleItems[cycle.id] {
                            var mergedItems = localItems.map { localItem in
                                firebaseItems.first(where: { $0.id == localItem.id }) ?? localItem
                            }
                            let newFirebaseItems = firebaseItems.filter { firebaseItem in
                                !mergedItems.contains(where: { mergedItem in mergedItem.id == firebaseItem.id })
                            }
                            mergedItems.append(contentsOf: newFirebaseItems)
                            newCycleItems[cycle.id] = mergedItems.sorted { $0.order < $1.order }
                        } else {
                            newCycleItems[cycle.id] = firebaseItems
                        }
                    } else if newCycleItems[cycle.id] == nil {
                        newCycleItems[cycle.id] = []
                    }
                    
                    if let groupedItemsDict = dict["groupedItems"] as? [String: [String: Any]] {
                        let firebaseGroupedItems = groupedItemsDict.compactMap { (groupKey, groupDict) -> GroupedItem? in
                            var mutableGroupDict = groupDict
                            mutableGroupDict["id"] = groupKey
                            return GroupedItem(dictionary: mutableGroupDict)
                        }
                        newGroupedItems[cycle.id] = firebaseGroupedItems
                    } else if newGroupedItems[cycle.id] == nil {
                        newGroupedItems[cycle.id] = []
                    }
                }
                DispatchQueue.main.async {
                    self.cycles = newCycles.sorted { $0.startDate < $1.startDate }
                    self.cycleItems = newCycleItems
                    self.groupedItems = newGroupedItems
                    self.saveCachedData()
                    self.syncError = nil
                }
            } else {
                DispatchQueue.main.async {
                    self.cycles = []
                    if self.cycleItems.isEmpty {
                        self.syncError = "No cycles found in Firebase or data is malformed."
                    } else {
                        self.syncError = nil
                    }
                }
            }
        } withCancel: { error in
            DispatchQueue.main.async {
                self.syncError = "Failed to sync cycles: \(error.localizedDescription)"
                self.isLoading = false
                print("Sync error: \(error.localizedDescription)")
                self.logToFile("Sync error: \(error.localizedDescription)")
            }
        }
        
        dbRef.child("units").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                let units = value.compactMap { (key, dict) -> Unit? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return Unit(dictionary: mutableDict)
                }
                DispatchQueue.main.async {
                    self.units = units.isEmpty ? [Unit(name: "mg"), Unit(name: "g")] : units
                }
            }
        }
        
        dbRef.child("users").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: [String: Any]] {
                let users = value.compactMap { (key, dict) -> User? in
                    var mutableDict = dict
                    mutableDict["id"] = key
                    return User(dictionary: mutableDict)
                }
                DispatchQueue.main.async {
                    self.users = users
                    if let userIdStr = UserDefaults.standard.string(forKey: "currentUserId"),
                       let userId = UUID(uuidString: userIdStr),
                       let updatedUser = users.first(where: { $0.id == userId }) {
                        self.currentUser = updatedUser
                        self.saveCurrentUserSettings()
                    }
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
        
        dbRef.child("consumptionLog").observe(.value) { snapshot in
            var newConsumptionLog: [UUID: [UUID: [LogEntry]]] = [:] // Start fresh, Firebase is source of truth
            for cycleSnapshot in snapshot.children {
                guard let cycleSnapshot = cycleSnapshot as? DataSnapshot,
                      let cycleId = UUID(uuidString: cycleSnapshot.key) else { continue }
                var cycleLog: [UUID: [LogEntry]] = [:]
                for itemSnapshot in cycleSnapshot.children {
                    guard let itemSnapshot = itemSnapshot as? DataSnapshot,
                          let itemId = UUID(uuidString: itemSnapshot.key),
                          let logsData = itemSnapshot.value as? [[String: Any]] else { continue }
                    var itemLogs: [LogEntry] = logsData.compactMap { dict -> LogEntry? in
                        guard let dateStr = dict["timestamp"] as? String,
                              let date = ISO8601DateFormatter().date(from: dateStr),
                              let userIdStr = dict["userId"] as? String,
                              let userId = UUID(uuidString: userIdStr) else { return nil }
                        return LogEntry(date: date, userId: userId)
                    }
                    // Initial deduplication from Firebase
                    itemLogs = Array(Set(itemLogs))
                    cycleLog[itemId] = itemLogs
                }
                if !cycleLog.isEmpty {
                    newConsumptionLog[cycleId] = cycleLog
                }
            }
            DispatchQueue.main.async {
                print("Firebase updated consumptionLog: \(newConsumptionLog)")
                self.logToFile("Firebase updated consumptionLog: \(newConsumptionLog)")
                // Apply pending updates, ensuring no duplicates
                for (cycleId, pendingItems) in self.pendingConsumptionLogUpdates {
                    if var cycleLog = newConsumptionLog[cycleId] {
                        for (itemId, pendingLogs) in pendingItems {
                            var mergedLogs = cycleLog[itemId] ?? []
                            mergedLogs.append(contentsOf: pendingLogs)
                            // Final deduplication after merge
                            mergedLogs = Array(Set(mergedLogs))
                            cycleLog[itemId] = mergedLogs
                        }
                        newConsumptionLog[cycleId] = cycleLog
                    } else {
                        var dedupedPendingItems: [UUID: [LogEntry]] = [:]
                        for (itemId, logs) in pendingItems {
                            dedupedPendingItems[itemId] = Array(Set(logs))
                        }
                        newConsumptionLog[cycleId] = dedupedPendingItems
                    }
                }
                self.consumptionLog = newConsumptionLog
                self.pendingConsumptionLogUpdates.removeAll() // Clear all pending updates after merge
                self.saveCachedData()
                self.objectWillChange.send()
            }
        }
        
        dbRef.child("categoryCollapsed").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: Bool] {
                DispatchQueue.main.async {
                    self.categoryCollapsed = value
                }
            }
        }
        
        dbRef.child("groupCollapsed").observe(.value) { snapshot in
            if snapshot.value != nil, let value = snapshot.value as? [String: Bool] {
                DispatchQueue.main.async {
                    let firebaseCollapsed = value.reduce(into: [UUID: Bool]()) { result, pair in
                        if let groupId = UUID(uuidString: pair.key) {
                            result[groupId] = pair.value
                        }
                    }
                    // Merge Firebase data, preserving local changes if they exist
                    for (groupId, isCollapsed) in firebaseCollapsed {
                        if self.groupCollapsed[groupId] == nil {
                            self.groupCollapsed[groupId] = isCollapsed
                        }
                    }
                }
            }
        }
        
        dbRef.child("treatmentTimerEnd").observe(.value) { snapshot in
            let formatter = ISO8601DateFormatter()
            DispatchQueue.main.async {
                if let timestamp = snapshot.value as? String,
                   let date = formatter.date(from: timestamp),
                   date > Date() {
                    if self.treatmentTimerEnd == nil || date > self.treatmentTimerEnd! {
                        self.treatmentTimerEnd = date
                    }
                } else {
                    // Clear timer state when Firebase value is removed or expired
                    self.treatmentTimerEnd = nil
                    self.treatmentTimerId = nil
                }
                self.saveTimerState()
                self.objectWillChange.send()
            }
        }
    }

    func setLastResetDate(_ date: Date) {
        guard let dbRef = dbRef else { return }
        dbRef.child("lastResetDate").setValue(ISO8601DateFormatter().string(from: date))
        lastResetDate = date
    }

    func setTreatmentTimerEnd(_ date: Date?) {
        guard let dbRef = dbRef else { return }
        if let date = date {
            dbRef.child("treatmentTimerEnd").setValue(ISO8601DateFormatter().string(from: date))
        } else {
            dbRef.child("treatmentTimerEnd").removeValue()
            self.treatmentTimerId = nil
        }
    }

    func addUnit(_ unit: Unit) {
        guard let dbRef = dbRef else { return }
        dbRef.child("units").child(unit.id.uuidString).setValue(unit.toDictionary())
    }

    func addItem(_ item: Item, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }), currentUser?.isAdmin == true else {
            completion(false)
            return
        }
        let currentItems = cycleItems[toCycleId] ?? []
        let newOrder = item.order == 0 ? currentItems.count : item.order
        let updatedItem = Item(
            id: item.id,
            name: item.name,
            category: item.category,
            dose: item.dose,
            unit: item.unit,
            weeklyDoses: item.weeklyDoses,
            order: newOrder
        )
        let itemRef = dbRef.child("cycles").child(toCycleId.uuidString).child("items").child(updatedItem.id.uuidString)
        itemRef.setValue(updatedItem.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding item \(updatedItem.id) to Firebase: \(error)")
                self.logToFile("Error adding item \(updatedItem.id) to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    if var items = self.cycleItems[toCycleId] {
                        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                            items[index] = updatedItem
                        } else {
                            items.append(updatedItem)
                        }
                        self.cycleItems[toCycleId] = items.sorted { $0.order < $1.order }
                    } else {
                        self.cycleItems[toCycleId] = [updatedItem]
                    }
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }

    func saveItems(_ items: [Item], toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }) else {
            completion(false)
            return
        }
        let itemsDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.toDictionary()) })
        dbRef.child("cycles").child(toCycleId.uuidString).child("items").setValue(itemsDict) { error, _ in
            if let error = error {
                print("Error saving items to Firebase: \(error)")
                self.logToFile("Error saving items to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    self.cycleItems[toCycleId] = items.sorted { $0.order < $1.order }
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }

    func removeItem(_ itemId: UUID, fromCycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == fromCycleId }), currentUser?.isAdmin == true else { return }
        dbRef.child("cycles").child(fromCycleId.uuidString).child("items").child(itemId.uuidString).removeValue()
        if var items = cycleItems[fromCycleId] {
            items.removeAll { $0.id == itemId }
            cycleItems[fromCycleId] = items
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    func addCycle(_ cycle: Cycle, copyItemsFromCycleId: UUID? = nil) {
        guard let dbRef = dbRef, currentUser?.isAdmin == true else { return }
        if cycles.contains(where: { $0.id == cycle.id }) {
            saveCycleToFirebase(cycle, withItems: cycleItems[cycle.id] ?? [], groupedItems: groupedItems[cycle.id] ?? [], previousCycleId: copyItemsFromCycleId)
            return
        }
        
        isAddingCycle = true
        cycles.append(cycle)
        var copiedItems: [Item] = []
        var copiedGroupedItems: [GroupedItem] = []
        
        let effectiveCopyId = copyItemsFromCycleId ?? (cycles.count > 1 ? cycles[cycles.count - 2].id : nil)
        
        if let fromCycleId = effectiveCopyId {
            dbRef.child("cycles").child(fromCycleId.uuidString).observeSingleEvent(of: .value) { snapshot in
                if let dict = snapshot.value as? [String: Any] {
                    if let itemsDict = dict["items"] as? [String: [String: Any]] {
                        copiedItems = itemsDict.compactMap { (itemKey, itemDict) -> Item? in
                            var mutableItemDict = itemDict
                            mutableItemDict["id"] = itemKey
                            return Item(dictionary: mutableItemDict)
                        }.map { Item(id: UUID(), name: $0.name, category: $0.category, dose: $0.dose, unit: $0.unit, weeklyDoses: $0.weeklyDoses, order: $0.order) }
                    }
                    if let groupedItemsDict = dict["groupedItems"] as? [String: [String: Any]] {
                        copiedGroupedItems = groupedItemsDict.compactMap { (groupKey, groupDict) -> GroupedItem? in
                            var mutableGroupDict = groupDict
                            mutableGroupDict["id"] = groupKey
                            return GroupedItem(dictionary: mutableGroupDict)
                        }.map { GroupedItem(id: UUID(), name: $0.name, category: $0.category, itemIds: $0.itemIds.map { _ in UUID() }) }
                    }
                }
                DispatchQueue.main.async {
                    self.cycleItems[cycle.id] = copiedItems
                    self.groupedItems[cycle.id] = copiedGroupedItems
                    self.saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
                }
            } withCancel: { error in
                DispatchQueue.main.async {
                    self.cycleItems[cycle.id] = copiedItems
                    self.groupedItems[cycle.id] = copiedGroupedItems
                    self.saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
                }
            }
        } else {
            cycleItems[cycle.id] = []
            groupedItems[cycle.id] = []
            saveCycleToFirebase(cycle, withItems: copiedItems, groupedItems: copiedGroupedItems, previousCycleId: effectiveCopyId)
        }
    }

    private func saveCycleToFirebase(_ cycle: Cycle, withItems items: [Item], groupedItems: [GroupedItem], previousCycleId: UUID?) {
        guard let dbRef = dbRef else { return }
        var cycleDict = cycle.toDictionary()
        let cycleRef = dbRef.child("cycles").child(cycle.id.uuidString)
        
        cycleRef.updateChildValues(cycleDict) { error, _ in
            if let error = error {
                DispatchQueue.main.async {
                    if let index = self.cycles.firstIndex(where: { $0.id == cycle.id }) {
                        self.cycles.remove(at: index)
                        self.cycleItems.removeValue(forKey: cycle.id)
                        self.groupedItems.removeValue(forKey: cycle.id)
                    }
                    self.isAddingCycle = false
                    self.objectWillChange.send()
                }
                return
            }
            
            if !items.isEmpty {
                let itemsDict = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.toDictionary()) })
                cycleRef.child("items").updateChildValues(itemsDict)
            }
            
            if !groupedItems.isEmpty {
                let groupedItemsDict = Dictionary(uniqueKeysWithValues: groupedItems.map { ($0.id.uuidString, $0.toDictionary()) })
                cycleRef.child("groupedItems").updateChildValues(groupedItemsDict)
            }
            
            if let prevId = previousCycleId, let prevItems = self.cycleItems[prevId], !prevItems.isEmpty {
                let prevCycleRef = dbRef.child("cycles").child(prevId.uuidString)
                prevCycleRef.child("items").observeSingleEvent(of: .value) { snapshot in
                    if snapshot.value == nil || (snapshot.value as? [String: [String: Any]])?.isEmpty ?? true {
                        let prevItemsDict = Dictionary(uniqueKeysWithValues: prevItems.map { ($0.id.uuidString, $0.toDictionary()) })
                        prevCycleRef.child("items").updateChildValues(prevItemsDict)
                    }
                }
            }
            
            DispatchQueue.main.async {
                if self.cycleItems[cycle.id] == nil || self.cycleItems[cycle.id]!.isEmpty {
                    self.cycleItems[cycle.id] = items
                }
                if self.groupedItems[cycle.id] == nil || self.groupedItems[cycle.id]!.isEmpty {
                    self.groupedItems[cycle.id] = groupedItems
                }
                self.saveCachedData()
                self.isAddingCycle = false
                self.objectWillChange.send()
            }
        }
    }

    func addUser(_ user: User) {
        guard let dbRef = dbRef else { return }
        let userRef = dbRef.child("users").child(user.id.uuidString)
        userRef.setValue(user.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding/updating user \(user.id): \(error)")
                self.logToFile("Error adding/updating user \(user.id): \(error)")
            }
        }
        DispatchQueue.main.async {
            if let index = self.users.firstIndex(where: { $0.id == user.id }) {
                self.users[index] = user
            } else {
                self.users.append(user)
            }
            if self.currentUser?.id == user.id {
                self.currentUser = user
            }
            self.saveCurrentUserSettings()
        }
    }

    func logConsumption(itemId: UUID, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef, let userId = currentUser?.id, cycles.contains(where: { $0.id == cycleId }) else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let logEntry = LogEntry(date: date, userId: userId)
        let today = Calendar.current.startOfDay(for: Date())

        // Fetch current Firebase state first
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var currentLogs = (snapshot.value as? [[String: String]]) ?? []
            let newEntryDict = ["timestamp": timestamp, "userId": userId.uuidString]
            
            // Remove any existing log for today to prevent duplicates
            currentLogs.removeAll { entry in
                if let logTimestamp = entry["timestamp"],
                   let logDate = formatter.date(from: logTimestamp) {
                    return Calendar.current.isDate(logDate, inSameDayAs: today)
                }
                return false
            }
            
            // Add the new entry
            currentLogs.append(newEntryDict)
            
            // Write to Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(currentLogs) { error, _ in
                if let error = error {
                    print("Failed to log consumption for \(itemId): \(error)")
                    self.logToFile("Failed to log consumption for \(itemId): \(error)")
                } else {
                    // Update local consumptionLog only after Firebase success
                    DispatchQueue.main.async {
                        if var cycleLog = self.consumptionLog[cycleId] {
                            var itemLogs = cycleLog[itemId] ?? []
                            // Remove today's existing logs locally
                            itemLogs.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
                            itemLogs.append(logEntry)
                            cycleLog[itemId] = itemLogs
                            self.consumptionLog[cycleId] = cycleLog
                        } else {
                            self.consumptionLog[cycleId] = [itemId: [logEntry]]
                        }
                        // Clear pending updates for this item
                        if var cyclePending = self.pendingConsumptionLogUpdates[cycleId] {
                            cyclePending.removeValue(forKey: itemId)
                            if cyclePending.isEmpty {
                                self.pendingConsumptionLogUpdates.removeValue(forKey: cycleId)
                            } else {
                                self.pendingConsumptionLogUpdates[cycleId] = cyclePending
                            }
                        }
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }

    func removeConsumption(itemId: UUID, cycleId: UUID, date: Date) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        
        // Update local consumptionLog
        if var cycleLogs = consumptionLog[cycleId], var itemLogs = cycleLogs[itemId] {
            itemLogs.removeAll { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .second) }
            if itemLogs.isEmpty {
                cycleLogs.removeValue(forKey: itemId)
            } else {
                cycleLogs[itemId] = itemLogs
            }
            consumptionLog[cycleId] = cycleLogs.isEmpty ? nil : cycleLogs
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        // Update Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if var entries = snapshot.value as? [[String: String]] {
                entries.removeAll { $0["timestamp"] == timestamp }
                dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(entries.isEmpty ? nil : entries) { error, _ in
                    if let error = error {
                        print("Failed to remove consumption for \(itemId): \(error)")
                        self.logToFile("Failed to remove consumption for \(itemId): \(error)")
                    }
                }
            }
        }
    }

    func setConsumptionLog(itemId: UUID, cycleId: UUID, entries: [LogEntry]) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let newEntries = Array(Set(entries)) // Deduplicate entries
        
        print("Setting consumption log for item \(itemId) in cycle \(cycleId) with entries: \(newEntries.map { $0.date })")
        
        // Fetch existing logs and update
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var existingEntries = (snapshot.value as? [[String: String]]) ?? []
            let newEntryDicts = newEntries.map { ["timestamp": formatter.string(from: $0.date), "userId": $0.userId.uuidString] }
            
            // Remove any existing entries not in the new list to prevent retaining old logs
            existingEntries = existingEntries.filter { existingEntry in
                guard let timestamp = existingEntry["timestamp"],
                      let date = formatter.date(from: timestamp) else { return false }
                return newEntries.contains { $0.date == date && $0.userId.uuidString == existingEntry["userId"] }
            }
            
            // Add new entries
            for newEntry in newEntryDicts {
                if !existingEntries.contains(where: { $0["timestamp"] == newEntry["timestamp"] && $0["userId"] == newEntry["userId"] }) {
                    existingEntries.append(newEntry)
                }
            }
            
            // Update local consumptionLog
            if var cycleLog = self.consumptionLog[cycleId] {
                cycleLog[itemId] = newEntries
                self.consumptionLog[cycleId] = cycleLog.isEmpty ? nil : cycleLog
            } else {
                self.consumptionLog[cycleId] = [itemId: newEntries]
            }
            if self.pendingConsumptionLogUpdates[cycleId] == nil {
                self.pendingConsumptionLogUpdates[cycleId] = [:]
            }
            self.pendingConsumptionLogUpdates[cycleId]![itemId] = newEntries
            self.saveCachedData()
            
            print("Updating Firebase with: \(existingEntries)")
            
            // Update Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(existingEntries.isEmpty ? nil : existingEntries) { error, _ in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Failed to set consumption log for \(itemId): \(error)")
                        self.logToFile("Failed to set consumption log for \(itemId): \(error)")
                        self.syncError = "Failed to sync log: \(error.localizedDescription)"
                    } else {
                        if var cyclePending = self.pendingConsumptionLogUpdates[cycleId] {
                            cyclePending.removeValue(forKey: itemId)
                            if cyclePending.isEmpty {
                                self.pendingConsumptionLogUpdates.removeValue(forKey: cycleId)
                            } else {
                                self.pendingConsumptionLogUpdates[cycleId] = cyclePending
                            }
                        }
                        print("Firebase update complete, local log: \(self.consumptionLog[cycleId]?[itemId] ?? [])")
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func setCategoryCollapsed(_ category: Category, isCollapsed: Bool) {
        guard let dbRef = dbRef else { return }
        categoryCollapsed[category.rawValue] = isCollapsed
        dbRef.child("categoryCollapsed").child(category.rawValue).setValue(isCollapsed)
    }
    
    func setGroupCollapsed(_ groupId: UUID, isCollapsed: Bool) {
        guard let dbRef = dbRef else { return }
        groupCollapsed[groupId] = isCollapsed
        dbRef.child("groupCollapsed").child(groupId.uuidString).setValue(isCollapsed)
    }

    func setReminderEnabled(_ category: Category, enabled: Bool) {
        guard var user = currentUser else { return }
        user.remindersEnabled[category] = enabled
        addUser(user)
    }

    func setReminderTime(_ category: Category, time: Date) {
        guard var user = currentUser else { return }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        let now = Date()
        var normalizedComponents = calendar.dateComponents([.year, .month, .day], from: now)
        normalizedComponents.hour = hour
        normalizedComponents.minute = minute
        normalizedComponents.second = 0
        if let normalizedTime = calendar.date(from: normalizedComponents) {
            user.reminderTimes[category] = normalizedTime
            addUser(user)
        }
    }

    func setTreatmentFoodTimerEnabled(_ enabled: Bool) {
        guard var user = currentUser else { return }
        user.treatmentFoodTimerEnabled = enabled
        addUser(user)
    }

    func setTreatmentTimerDuration(_ duration: TimeInterval) {
        guard var user = currentUser else { return }
        user.treatmentTimerDuration = duration
        addUser(user)
    }

    func addGroupedItem(_ groupedItem: GroupedItem, toCycleId: UUID, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == toCycleId }), currentUser?.isAdmin == true else {
            completion(false)
            return
        }
        let groupRef = dbRef.child("cycles").child(toCycleId.uuidString).child("groupedItems").child(groupedItem.id.uuidString)
        groupRef.setValue(groupedItem.toDictionary()) { error, _ in
            if let error = error {
                print("Error adding grouped item \(groupedItem.id) to Firebase: \(error)")
                self.logToFile("Error adding grouped item \(groupedItem.id) to Firebase: \(error)")
                completion(false)
            } else {
                DispatchQueue.main.async {
                    var cycleGroups = self.groupedItems[toCycleId] ?? []
                    if let index = cycleGroups.firstIndex(where: { $0.id == groupedItem.id }) {
                        cycleGroups[index] = groupedItem
                    } else {
                        cycleGroups.append(groupedItem)
                    }
                    self.groupedItems[toCycleId] = cycleGroups
                    self.saveCachedData()
                    self.objectWillChange.send()
                    completion(true)
                }
            }
        }
    }

    func removeGroupedItem(_ groupId: UUID, fromCycleId: UUID) {
        guard let dbRef = dbRef, cycles.contains(where: { $0.id == fromCycleId }), currentUser?.isAdmin == true else { return }
        dbRef.child("cycles").child(fromCycleId.uuidString).child("groupedItems").child(groupId.uuidString).removeValue()
        if var groups = groupedItems[fromCycleId] {
            groups.removeAll { $0.id == groupId }
            groupedItems[fromCycleId] = groups
            saveCachedData()
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    func logGroupedItem(_ groupedItem: GroupedItem, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef else { return }
        let today = Calendar.current.startOfDay(for: date)
        let isChecked = groupedItem.itemIds.allSatisfy { itemId in
            self.consumptionLog[cycleId]?[itemId]?.contains { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? false
        }
        
        print("logGroupedItem: Group \(groupedItem.name) isChecked=\(isChecked)")
        self.logToFile("logGroupedItem: Group \(groupedItem.name) isChecked=\(isChecked)")
        
        if isChecked {
            for itemId in groupedItem.itemIds {
                if let logs = self.consumptionLog[cycleId]?[itemId], !logs.isEmpty {
                    print("Clearing all \(logs.count) logs for item \(itemId)")
                    self.logToFile("Clearing all \(logs.count) logs for item \(itemId)")
                    if var itemLogs = self.consumptionLog[cycleId] {
                        itemLogs[itemId] = []
                        if itemLogs[itemId]?.isEmpty ?? true {
                            itemLogs.removeValue(forKey: itemId)
                        }
                        self.consumptionLog[cycleId] = itemLogs.isEmpty ? nil : itemLogs
                    }
                    let path = "consumptionLog/\(cycleId.uuidString)/\(itemId.uuidString)"
                    dbRef.child(path).removeValue { error, _ in
                        if let error = error {
                            print("Failed to clear logs for \(itemId): \(error)")
                            self.logToFile("Failed to clear logs for \(itemId): \(error)")
                        } else {
                            print("Successfully cleared logs for \(itemId) in Firebase")
                            self.logToFile("Successfully cleared logs for \(itemId) in Firebase")
                        }
                    }
                }
            }
        } else {
            for itemId in groupedItem.itemIds {
                if !(self.consumptionLog[cycleId]?[itemId]?.contains { Calendar.current.isDate($0.date, inSameDayAs: today) } ?? false) {
                    print("Logging item \(itemId) for \(date)")
                    self.logToFile("Logging item \(itemId) for \(date)")
                    self.logConsumption(itemId: itemId, cycleId: cycleId, date: date)
                }
            }
        }
        self.saveCachedData()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func resetDaily() {
        let today = Calendar.current.startOfDay(for: Date())
        setLastResetDate(today)
        
        for (cycleId, itemLogs) in consumptionLog {
            var updatedItemLogs = itemLogs
            for (itemId, logs) in itemLogs {
                updatedItemLogs[itemId] = logs.filter { !Calendar.current.isDate($0.date, inSameDayAs: today) }
                if updatedItemLogs[itemId]?.isEmpty ?? false {
                    updatedItemLogs.removeValue(forKey: itemId)
                }
            }
            if let dbRef = dbRef {
                let formatter = ISO8601DateFormatter()
                let updatedLogDict = updatedItemLogs.mapValues { entries in
                    entries.map { ["timestamp": formatter.string(from: $0.date), "userId": $0.userId.uuidString] }
                }
                dbRef.child("consumptionLog").child(cycleId.uuidString).setValue(updatedLogDict.isEmpty ? nil : updatedLogDict)
            }
            consumptionLog[cycleId] = updatedItemLogs.isEmpty ? nil : updatedItemLogs
        }
        
        Category.allCases.forEach { category in
            setCategoryCollapsed(category, isCollapsed: false)
        }
        
        if let endDate = treatmentTimerEnd {
            if endDate > Date() {
                print("Preserving active timer ending at: \(endDate)")
                logToFile("Preserving active timer ending at: \(endDate)")
            } else {
                treatmentTimerEnd = nil
                treatmentTimerId = nil
            }
        }
        
        saveCachedData()
        saveTimerState()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func checkAndResetIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if lastResetDate == nil || !Calendar.current.isDate(lastResetDate!, inSameDayAs: today) {
            resetDaily()
        }
    }

    func currentCycleId() -> UUID? {
        cycles.last?.id
    }

    func verifyFirebaseState() {
        guard let dbRef = dbRef else { return }
        dbRef.child("cycles").observeSingleEvent(of: .value) { snapshot in
            if let value = snapshot.value as? [String: [String: Any]] {
                print("Final Firebase cycles state: \(value)")
                self.logToFile("Final Firebase cycles state: \(value)")
            } else {
                print("Final Firebase cycles state is empty or missing")
                self.logToFile("Final Firebase cycles state is empty or missing")
            }
        }
    }

    func rescheduleDailyReminders() {
        guard let user = currentUser else { return }
        for category in Category.allCases where user.remindersEnabled[category] == true {
            if let view = UIApplication.shared.windows.first?.rootViewController?.view {
                RemindersView(appData: self).scheduleReminder(for: category)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 24 * 3600) {
            self.rescheduleDailyReminders()
        }
    }
}

struct TimerState: Codable {
    let endDate: Date?
    let timerId: String?
}
extension AppData {
    // This method logs a consumption for a specific item without triggering group logging behavior
    // Add or replace this method in your AppData extension
    func logIndividualConsumption(itemId: UUID, cycleId: UUID, date: Date = Date()) {
        guard let dbRef = dbRef, let userId = currentUser?.id, cycles.contains(where: { $0.id == cycleId }) else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let logEntry = LogEntry(date: date, userId: userId)
        let calendar = Calendar.current
        let logDay = calendar.startOfDay(for: date)
        
        // Check if the item already has a log for this day locally
        if let existingLogs = consumptionLog[cycleId]?[itemId] {
            let existingLogForDay = existingLogs.first { calendar.isDate($0.date, inSameDayAs: logDay) }
            if existingLogForDay != nil {
                print("Item \(itemId) already has a log for \(logDay), skipping")
                return
            }
        }
        
        // Fetch current logs from Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            var currentLogs = (snapshot.value as? [[String: String]]) ?? []
            
            // Deduplicate entries by day in case there are already duplicates in Firebase
            var entriesByDay = [String: [String: String]]()
            
            for entry in currentLogs {
                if let entryTimestamp = entry["timestamp"],
                   let entryDate = formatter.date(from: entryTimestamp) {
                    let dayKey = formatter.string(from: calendar.startOfDay(for: entryDate))
                    entriesByDay[dayKey] = entry
                }
            }
            
            // Check if there's already an entry for this day
            let todayKey = formatter.string(from: logDay)
            if entriesByDay[todayKey] != nil {
                print("Firebase already has an entry for \(logDay), skipping")
                return
            }
            
            // Add new entry
            let newEntryDict = ["timestamp": timestamp, "userId": userId.uuidString]
            entriesByDay[todayKey] = newEntryDict
            
            // Convert back to array
            let deduplicatedLogs = Array(entriesByDay.values)
            
            // Update Firebase
            dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(deduplicatedLogs) { error, _ in
                if let error = error {
                    print("Error logging consumption for \(itemId): \(error)")
                    self.logToFile("Error logging consumption for \(itemId): \(error)")
                } else {
                    // Update local data after Firebase success
                    DispatchQueue.main.async {
                        if var cycleLog = self.consumptionLog[cycleId] {
                            if var itemLogs = cycleLog[itemId] {
                                // Remove any existing logs for the same day before adding the new one
                                itemLogs.removeAll { calendar.isDate($0.date, inSameDayAs: logDay) }
                                itemLogs.append(logEntry)
                                cycleLog[itemId] = itemLogs
                            } else {
                                cycleLog[itemId] = [logEntry]
                            }
                            self.consumptionLog[cycleId] = cycleLog
                        } else {
                            self.consumptionLog[cycleId] = [itemId: [logEntry]]
                        }
                        
                        self.saveCachedData()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    // This method enhances the deletion of consumption logs to ensure consistent state
    func removeIndividualConsumption(itemId: UUID, cycleId: UUID, date: Date) {
        guard let dbRef = dbRef else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: date)
        let calendar = Calendar.current
        
        // Update local consumptionLog first
        if var cycleLogs = consumptionLog[cycleId], var itemLogs = cycleLogs[itemId] {
            itemLogs.removeAll { calendar.isDate($0.date, equalTo: date, toGranularity: .second) }
            if itemLogs.isEmpty {
                cycleLogs.removeValue(forKey: itemId)
            } else {
                cycleLogs[itemId] = itemLogs
            }
            consumptionLog[cycleId] = cycleLogs.isEmpty ? nil : cycleLogs
            saveCachedData()
        }
        
        // Then update Firebase
        dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).observeSingleEvent(of: .value) { snapshot in
            if var entries = snapshot.value as? [[String: String]] {
                // Remove entries that match the date (could be multiple if there were duplicates)
                entries.removeAll { entry in
                    guard let entryTimestamp = entry["timestamp"],
                          let entryDate = formatter.date(from: entryTimestamp) else {
                        return false
                    }
                    return calendar.isDate(entryDate, equalTo: date, toGranularity: .second)
                }
                
                // Update or remove the entry in Firebase
                if entries.isEmpty {
                    dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).removeValue { error, _ in
                        if let error = error {
                            print("Error removing consumption for \(itemId): \(error)")
                            self.logToFile("Error removing consumption for \(itemId): \(error)")
                        } else {
                            print("Successfully removed all logs for item \(itemId)")
                            self.logToFile("Successfully removed all logs for item \(itemId)")
                        }
                    }
                } else {
                    dbRef.child("consumptionLog").child(cycleId.uuidString).child(itemId.uuidString).setValue(entries) { error, _ in
                        if let error = error {
                            print("Error updating consumption for \(itemId): \(error)")
                            self.logToFile("Error updating consumption for \(itemId): \(error)")
                        } else {
                            print("Successfully updated logs for item \(itemId)")
                            self.logToFile("Successfully updated logs for item \(itemId)")
                        }
                    }
                }
            }
        }
        
        // Ensure UI updates
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
