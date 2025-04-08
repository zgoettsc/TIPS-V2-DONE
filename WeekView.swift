import SwiftUI

struct WeekView: View {
    @ObservedObject var appData: AppData
    @State private var currentWeekOffset: Int = 0
    @State private var currentCycleOffset = 0

    let totalWidth = UIScreen.main.bounds.width
    let itemColumnWidth: CGFloat = 130
    var dayColumnWidth: CGFloat {
        (totalWidth - itemColumnWidth) / 7
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Week View")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                Text("Cycle \(displayedCycleNumber())")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            HStack {
                Button(action: { withAnimation { previousWeek() } }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .padding(.horizontal, 4)
                }

                Spacer()

                Text(weekRangeText())
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { nextWeek() } }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)

            HStack(spacing: 0) {
                Text("Items")
                    .frame(width: itemColumnWidth, alignment: .leading)
                    .padding(.leading, 12)
                ForEach(0..<7) { offset in
                    let date = dayDate(for: offset)
                    let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
                    VStack(spacing: 2) {
                        Text(weekDays()[offset])
                            .font(.caption2)
                            .fontWeight(.bold)
                        Text(dayNumberFormatter.string(from: date))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .frame(width: dayColumnWidth, height: 40)
                    .background(isToday ? Color.yellow.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
            }
            Divider()

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Category.allCases, id: \.self) { category in
                        HStack {
                            Text(category.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(.label))
                                .padding(.leading, 12)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(.systemGray6))

                        let categoryItems = itemsForSelectedCycle().filter { $0.category == category }
                        if categoryItems.isEmpty {
                            Text("No items added")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.leading)
                                .padding(.bottom, 6)
                        } else {
                            ForEach(categoryItems) { item in
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.caption)
                                            .foregroundColor(category == .recommended && weeklyDoseCount(for: item) >= 3 ? .green : .primary)
                                        if let doseText = itemDisplayText(item: item).components(separatedBy: " - ").last {
                                            Text(doseText)
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(width: itemColumnWidth, alignment: .leading)
                                    .padding(.leading, 12)

                                    ForEach(0..<7) { dayOffset in
                                        let date = dayDate(for: dayOffset)
                                        let isLogged = isItemLogged(item: item, on: date)
                                        let isToday = Calendar.current.isDate(date, inSameDayAs: Date())

                                        Image(systemName: isLogged ? "checkmark" : "")
                                            .foregroundColor(isLogged ? .green : .clear)
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: dayColumnWidth, height: 36)
                                            .background(isToday ? Color.yellow.opacity(0.2) : Color.clear)
                                            .border(Color.gray.opacity(0.2))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    HStack(spacing: 24) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.yellow.opacity(0.4))
                                .frame(width: 12, height: 12)
                            Text("Current Day")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Logged Item")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
                .padding(.bottom, 12)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    withAnimation {
                        if value.translation.width < -50 {
                            nextWeek()
                        } else if value.translation.width > 50 {
                            previousWeek()
                        }
                    }
                }
        )
        .onAppear {
            if let currentCycle = appData.cycles.last {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let cycleStartDay = calendar.startOfDay(for: currentCycle.startDate)
                let daysSinceStart = calendar.dateComponents([.day], from: cycleStartDay, to: today).day ?? 0
                let currentWeek = (daysSinceStart / 7) + 1
                currentCycleOffset = 0
                currentWeekOffset = currentWeek - 1
            }
        }
    }

    private let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    func weekStartDate() -> Date {
        guard let currentCycle = selectedCycle() else { return Date() }
        return Calendar.current.date(byAdding: .weekOfYear, value: currentWeekOffset, to: Calendar.current.startOfDay(for: currentCycle.startDate)) ?? Date()
    }

    func dayDate(for offset: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate()) ?? Date()
    }

    func weekDays() -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate()) ?? Date()
            return formatter.string(from: date)
        }
    }

    func displayedCycleNumber() -> Int {
        guard !appData.cycles.isEmpty else { return 0 }
        let index = max(0, appData.cycles.count - 1 + currentCycleOffset)
        return appData.cycles[index].number
    }

    func selectedCycle() -> Cycle? {
        guard !appData.cycles.isEmpty else { return nil }
        let index = max(0, appData.cycles.count - 1 + currentCycleOffset)
        return appData.cycles[index]
    }

    func itemsForSelectedCycle() -> [Item] {
        guard let cycle = selectedCycle() else { return [] }
        return appData.cycleItems[cycle.id] ?? []
    }

    func isItemLogged(item: Item, on date: Date) -> Bool {
        guard let cycle = selectedCycle() else { return false }
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let logs = appData.consumptionLog[cycle.id]?[item.id] ?? []
        return logs.contains { Calendar.current.isDate($0.date, inSameDayAs: normalizedDate) }
    }

    func weeklyDoseCount(for item: Item) -> Int {
        guard let cycle = selectedCycle() else { return 0 }
        let weekStart = weekStartDate()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let weekEndOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: weekEnd) ?? weekEnd
        let logs = appData.consumptionLog[cycle.id]?[item.id] ?? []
        return logs.filter { $0.date >= weekStart && $0.date <= weekEndOfDay }.count
    }

    func itemDisplayText(item: Item) -> String {
        if let dose = item.dose, let unit = item.unit {
            return "\(item.name) - \(String(format: "%.1f", dose)) \(unit)"
        } else if item.category == .treatment, let unit = item.unit {
            let week = displayedWeekNumber()
            if let weeklyDose = item.weeklyDoses?[week] {
                return "\(item.name) - \(String(format: "%.1f", weeklyDose)) \(unit)"
            }
        }
        return item.name
    }

    func weekRangeText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate())
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate()) ?? Date())
        let year = Calendar.current.component(.year, from: weekStartDate())
        return "\(start) - \(end), \(year)"
    }

    func displayedWeekNumber() -> Int {
        return currentWeekOffset + 1
    }

    func previousWeek() {
        if currentWeekOffset > 0 {
            currentWeekOffset -= 1
        } else if currentCycleOffset > -maxCyclesBefore() {
            currentCycleOffset -= 1
            currentWeekOffset = maxWeeksBefore()
        }
    }

    func nextWeek() {
        if currentWeekOffset < maxWeeksBefore() {
            currentWeekOffset += 1
        } else if currentCycleOffset < 0 {
            currentCycleOffset += 1
            currentWeekOffset = 0
        }
    }

    func maxWeeksBefore() -> Int {
        guard let cycle = selectedCycle() else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: cycle.startDate, to: cycle.foodChallengeDate).day ?? 0
        return max(0, days / 7)
    }

    func maxCyclesBefore() -> Int {
        return appData.cycles.count - 1
    }
}

