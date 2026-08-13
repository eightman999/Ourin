import SwiftUI
import AppKit

enum CalendarGrid {
    static func days(
        in month: Date,
        calendar: Calendar = .current,
        count: Int = 42
    ) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -leading, to: interval.start) else {
            return []
        }
        return (0..<max(0, count)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: first)
        }
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    static func isSameMonth(_ date: Date, as month: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.year, from: date) == calendar.component(.year, from: month)
            && calendar.component(.month, from: date) == calendar.component(.month, from: month)
    }
}

final class CalendarWindowModel: ObservableObject {
    @Published var displayedMonth: Date
    @Published var selectedDate: Date
    @Published private(set) var schedules: [CalendarSchedule] = []
    @Published private(set) var lastRefreshMessage = ""

    private let loadSchedules: () -> CalendarScheduleRefreshResult
    private let readSchedule: (CalendarSchedule) -> Bool

    init(
        now: Date = Date(),
        loadSchedules: @escaping () -> CalendarScheduleRefreshResult = {
            EventBridge.shared.refreshCalendarSchedules()
        },
        readSchedule: @escaping (CalendarSchedule) -> Bool = {
            EventBridge.shared.readCalendarSchedule(id: $0.id)
        }
    ) {
        self.displayedMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        self.selectedDate = now
        self.loadSchedules = loadSchedules
        self.readSchedule = readSchedule
    }

    func refresh() {
        let result = loadSchedules()
        schedules = result.schedules
        if result.rejectedLineNumbers.isEmpty {
            lastRefreshMessage = "\(result.schedules.count)件"
        } else {
            let lines = result.rejectedLineNumbers.map(String.init).joined(separator: ", ")
            lastRefreshMessage = "\(result.schedules.count)件（無効な行: \(lines)）"
        }
    }

    func moveMonth(by value: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = next
        selectedDate = next
    }

    func selectToday(now: Date = Date()) {
        displayedMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        selectedDate = now
    }

    func schedules(on date: Date) -> [CalendarSchedule] {
        schedules.filter {
            CalendarGrid.isSameDay(
                Calendar.current.date(
                    from: DateComponents(year: $0.year, month: $0.month, day: $0.day)
                ) ?? .distantPast,
                date
            )
        }
        .sorted { lhs, rhs in
            let left = (lhs.startHour ?? 24) * 60 + (lhs.startMinute ?? 0)
            let right = (rhs.startHour ?? 24) * 60 + (rhs.startMinute ?? 0)
            return left == right ? lhs.caption < rhs.caption : left < right
        }
    }

    @discardableResult
    func read(_ schedule: CalendarSchedule) -> Bool {
        readSchedule(schedule)
    }
}

struct CalendarWindowView: View {
    @ObservedObject var model: CalendarWindowModel
    private let calendar = Calendar.current

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: model.displayedMonth)
    }

    private var weekdayTitles: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = max(1, min(calendar.firstWeekday, symbols.count)) - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 16) {
                monthGrid
                selectedScheduleList
                    .frame(width: 220)
            }
            .padding(16)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Button {
                model.moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("前月")

            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 130)

            Button {
                model.moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("次月")

            Button("今日") {
                model.selectToday()
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(model.lastRefreshMessage)
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .font(.callout)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("予定を更新")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var monthGrid: some View {
        let days = CalendarGrid.days(in: model.displayedMonth, calendar: calendar)
        return VStack(spacing: 6) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(Array(weekdayTitles.enumerated()), id: \.offset) { index, title in
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(index == 0 ? .red : (index == 6 ? .blue : Color(NSColor.secondaryLabelColor)))
                }

                ForEach(days, id: \.self) { date in
                    CalendarDayCell(
                        date: date,
                        schedules: model.schedules(on: date),
                        isCurrentMonth: CalendarGrid.isSameMonth(date, as: model.displayedMonth),
                        isToday: calendar.isDateInToday(date),
                        isSelected: CalendarGrid.isSameDay(date, model.selectedDate),
                        onSelect: { model.selectedDate = date },
                        onRead: { schedule in _ = model.read(schedule) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedScheduleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDateTitle)
                .font(.headline)
            Divider()
            let selected = model.schedules(on: model.selectedDate)
            if selected.isEmpty {
                Text("予定はありません")
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .font(.callout)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selected) { schedule in
                            CalendarScheduleRow(
                                schedule: schedule,
                                onRead: { _ = model.read(schedule) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.quaternaryLabelColor).opacity(0.35))
        )
    }

    private var selectedDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: model.selectedDate)
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let schedules: [CalendarSchedule]
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onRead: (CalendarSchedule) -> Void

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(dayNumber)
                        .font(.callout.weight(isToday ? .bold : .regular))
                        .foregroundColor(isCurrentMonth ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                    Spacer()
                    if !schedules.isEmpty {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                ForEach(schedules.prefix(2)) { schedule in
                    Text(schedule.caption)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(isCurrentMonth ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                        .onHover { hovering in
                            if hovering { onRead(schedule) }
                        }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct CalendarScheduleRow: View {
    let schedule: CalendarSchedule
    let onRead: () -> Void

    private var timeText: String {
        guard let hour = schedule.startHour, let minute = schedule.startMinute else {
            return "終日"
        }
        let start = String(format: "%02d:%02d", hour, minute)
        guard let endHour = schedule.endHour, let endMinute = schedule.endMinute else {
            return start
        }
        return "\(start)–\(String(format: "%02d:%02d", endHour, endMinute))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
                Text(schedule.type)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Text(schedule.caption)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            if !schedule.subtitle.isEmpty {
                Text(schedule.subtitle)
                    .font(.caption)
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(3)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .onHover { hovering in
            if hovering { onRead() }
        }
    }
}

final class CalendarWindowController: NSWindowController {
    static let shared = CalendarWindowController()

    private let model = CalendarWindowModel()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.show() }
            return
        }

        if window == nil {
            let hosting = NSHostingController(rootView: CalendarWindowView(model: model))
            let calendarWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            calendarWindow.title = "カレンダー"
            calendarWindow.contentViewController = hosting
            calendarWindow.isReleasedWhenClosed = false
            calendarWindow.center()
            window = calendarWindow
        }

        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
