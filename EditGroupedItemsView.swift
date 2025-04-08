//
//  EditGroupedItemsView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 3/14/25.
//


import SwiftUI

struct EditGroupedItemsView: View {
    @ObservedObject var appData: AppData
    let cycleId: UUID
    @State private var showingAddGroup = false
    @State private var editingGroup: GroupedItem?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            ForEach(Category.allCases, id: \.self) { category in
                Section(header: Text(category.rawValue)) {
                    let groups = (appData.groupedItems[cycleId] ?? []).filter { $0.category == category }
                    if groups.isEmpty {
                        Text("No grouped items")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(groups) { group in
                            Button(action: { editingGroup = group }) {
                                Text(group.name)
                            }
                        }
                        .onDelete { offsets in
                            let groupsToDelete = offsets.map { groups[$0] }
                            groupsToDelete.forEach { appData.removeGroupedItem($0.id, fromCycleId: cycleId) }
                        }
                    }
                }
            }
            Button("Add Grouped Item") { showingAddGroup = true }
        }
        .navigationTitle("Edit Grouped Items")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddGroup) {
            AddGroupedItemView(appData: appData, cycleId: cycleId)
        }
        .sheet(item: $editingGroup) { group in
            AddGroupedItemView(appData: appData, cycleId: cycleId, group: group)
        }
    }
}

struct AddGroupedItemView: View {
    @ObservedObject var appData: AppData
    let cycleId: UUID
    @State private var group: GroupedItem?
    @State private var name: String
    @State private var category: Category = .maintenance
    @State private var selectedItemIds: [UUID] = []
    @Environment(\.dismiss) var dismiss
    
    init(appData: AppData, cycleId: UUID, group: GroupedItem? = nil) {
        self.appData = appData
        self.cycleId = cycleId
        self._group = State(initialValue: group)
        self._name = State(initialValue: group?.name ?? "")
        self._category = State(initialValue: group?.category ?? .maintenance)
        self._selectedItemIds = State(initialValue: group?.itemIds ?? [])
    }
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Group Name (e.g., Muffin)", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                Section(header: Text("Select Items")) {
                    let categoryItems = appData.cycleItems[cycleId]?.filter { $0.category == category } ?? []
                    if categoryItems.isEmpty {
                        Text("No items in this category")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(categoryItems) { item in
                            MultipleSelectionRow(
                                title: itemDisplayText(item: item),
                                isSelected: selectedItemIds.contains(item.id)
                            ) {
                                if selectedItemIds.contains(item.id) {
                                    selectedItemIds.removeAll { $0 == item.id }
                                } else {
                                    selectedItemIds.append(item.id)
                                }
                            }
                        }
                    }
                }
                if group != nil {
                    Button("Delete Group", role: .destructive) {
                        if let groupId = group?.id {
                            appData.removeGroupedItem(groupId, fromCycleId: cycleId)
                        }
                        dismiss()
                    }
                }
            }
            .navigationTitle(group == nil ? "Add Group" : "Edit Group")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let newGroup = GroupedItem(
                            id: group?.id ?? UUID(),
                            name: name,
                            category: category,
                            itemIds: selectedItemIds
                        )
                        appData.addGroupedItem(newGroup, toCycleId: cycleId)
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedItemIds.isEmpty)
                }
            }
        }
    }
    
    private func itemDisplayText(item: Item) -> String {
        if let dose = item.dose, let unit = item.unit {
            return "\(item.name) - \(String(format: "%.1f", dose)) \(unit)"
        }
        return item.name
    }
}

struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

struct EditGroupedItemsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EditGroupedItemsView(appData: AppData(), cycleId: UUID())
        }
    }
}