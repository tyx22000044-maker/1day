import Foundation
import SwiftData

@Model
final class PlanItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String

    var dueDate: Date?
    var statusRawValue: String
    var priorityRawValue: String

    var reminderTime: Date?

    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(title: String,
         notes: String = "",
         dueDate: Date? = nil,
         status: ItemStatus = .pending,
         priority: Priority = .none,
         reminderTime: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.statusRawValue = status.rawValue
        self.priorityRawValue = priority.rawValue
        self.reminderTime = reminderTime
        self.createdAt = Date()
        self.updatedAt = Date()
        self.completedAt = nil
    }

    // MARK: - Computed Properties

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRawValue) ?? .pending }
        set {
            statusRawValue = newValue.rawValue
            if newValue == .completed && completedAt == nil {
                completedAt = Date()
            } else if newValue == .pending {
                completedAt = nil
            }
        }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRawValue) ?? .none }
        set { priorityRawValue = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool {
        isDue(on: .now)
    }

    func isDue(on date: Date) -> Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDate(dueDate, inSameDayAs: date)
    }

    func isOverdue(asOf date: Date) -> Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: date)
    }

    var isUnscheduled: Bool {
        dueDate == nil
    }
}
