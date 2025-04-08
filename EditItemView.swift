import SwiftUI

struct EditItemView: View {
    @ObservedObject var appData: AppData
    @State var item: Item
    let cycleId: UUID
    @State private var name: String
    @State private var dose: String
    @State private var selectedUnit: Unit?
    @State private var selectedCategory: Category
    @State private var showingDeleteConfirmation = false
    @State private var inputMode: InputMode = .decimal // New state for mode
    @State private var selectedFraction: Fraction? // New state for fraction picker
    @Environment(\.dismiss) var dismiss
    
    enum InputMode: String, CaseIterable {
        case decimal = "Decimal"
        case fraction = "Fraction"
    }
    
    init(appData: AppData, item: Item, cycleId: UUID) {
        self.appData = appData
        self._item = State(initialValue: item)
        self.cycleId = cycleId
        self._name = State(initialValue: item.name)
        self._dose = State(initialValue: item.dose.map { String($0) } ?? "")
        self._selectedUnit = State(initialValue: appData.units.first { $0.name == item.unit })
        self._selectedCategory = State(initialValue: item.category)
        if let dose = item.dose, let fraction = Fraction.fractionForDecimal(dose) {
            self._selectedFraction = State(initialValue: fraction)
            self._inputMode = State(initialValue: .fraction)
        } else {
            self._selectedFraction = State(initialValue: nil)
            self._inputMode = State(initialValue: .decimal)
        }
    }
    
    var body: some View {
        Form {
            Section(header: Text("Item Details")) {
                TextField("Item Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Picker("Input Mode", selection: $inputMode) {
                    ForEach(InputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                if inputMode == .decimal {
                    HStack {
                        TextField("Dose", text: $dose)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Picker("Unit", selection: $selectedUnit) {
                            Text("Select Unit").tag(nil as Unit?)
                            ForEach(appData.units, id: \.self) { unit in
                                Text(unit.name).tag(unit as Unit?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                } else {
                    HStack {
                        Picker("Dose", selection: $selectedFraction) {
                            Text("Select fraction").tag(nil as Fraction?)
                            ForEach(Fraction.commonFractions) { fraction in
                                Text(fraction.displayString).tag(fraction as Fraction?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        Picker("Unit", selection: $selectedUnit) {
                            Text("Select Unit").tag(nil as Unit?)
                            ForEach(appData.units, id: \.self) { unit in
                                Text(unit.name).tag(unit as Unit?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                NavigationLink(destination: AddUnitFromItemView(appData: appData, selectedUnit: $selectedUnit)) {
                    Text("Add a Unit")
                }
            }
            
            Section(header: Text("Category")) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(Category.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section {
                Button("Delete Item", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .alert("Delete \(name)?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        appData.removeItem(item.id, fromCycleId: cycleId)
                        dismiss()
                    }
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
        .navigationTitle("Edit Item")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    guard let doseValue = inputMode == .decimal ? Double(dose) : selectedFraction?.decimalValue,
                          !name.isEmpty else { return }
                    let updatedItem = Item(
                        id: item.id,
                        name: name,
                        category: selectedCategory,
                        dose: doseValue,
                        unit: selectedUnit?.name,
                        weeklyDoses: nil
                    )
                    appData.addItem(updatedItem, toCycleId: cycleId) { success in
                        if success {
                            DispatchQueue.main.async {
                                dismiss()
                            }
                        }
                    }
                }
                .disabled(name.isEmpty || (inputMode == .decimal && (dose.isEmpty || Double(dose) == nil)) || (inputMode == .fraction && selectedFraction == nil) || selectedUnit == nil)
            }
        }
    }
}

struct EditItemView_Previews: PreviewProvider {
    static var previews: some View {
        EditItemView(appData: AppData(), item: Item(name: "Test", category: .medicine), cycleId: UUID())
    }
}
