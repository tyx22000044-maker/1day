import Foundation
import SwiftData

struct PlanItemDraft: Equatable {
    var title: String
    var notes: String = ""
    var dueDate: Date?
    var reminderTime: Date?
    var priority: Priority = .none
}

enum PlanItemValidator {
    static func error(for draft: PlanItemDraft) -> String? {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "任务标题不能为空。"
        }
        return nil
    }
}

enum PlanItemService {
    @discardableResult
    static func createTask(_ draft: PlanItemDraft, in context: ModelContext) -> PlanItem? {
        guard PlanItemValidator.error(for: draft) == nil else { return nil }
        return createTask(
            title: draft.title,
            notes: draft.notes,
            dueDate: draft.dueDate,
            priority: draft.priority,
            reminderTime: draft.reminderTime,
            in: context
        )
    }
    @discardableResult
    static func createTask(
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: Priority = .none,
        reminderTime: Date? = nil,
        in context: ModelContext
    ) -> PlanItem {
        let item = PlanItem(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            reminderTime: reminderTime
        )
        context.insert(item)
        NotificationService.scheduleTaskReminder(for: item)
        AppLogger.data("Created task: \(item.id)")
        return item
    }

    static func toggleCompletion(_ item: PlanItem) {
        setCompletion(item, isCompleted: !item.isCompleted)
    }

    static func setCompletion(_ item: PlanItem, isCompleted: Bool) {
        item.status = isCompleted ? .completed : .pending
        item.updatedAt = Date()
        if isCompleted {
            NotificationService.cancelTaskReminder(for: item)
        } else {
            NotificationService.scheduleTaskReminder(for: item)
        }
        AppLogger.data("Updated task completion: \(item.id), completed: \(isCompleted)")
    }

    static func refreshReminder(for item: PlanItem) {
        if item.isCompleted {
            NotificationService.cancelTaskReminder(for: item)
        } else {
            NotificationService.scheduleTaskReminder(for: item)
        }
    }

    static func updateSchedule(for item: PlanItem, dueDate: Date?, reminderTime: Date? = nil) {
        item.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        item.reminderTime = reminderTime
        item.updatedAt = .now
        refreshReminder(for: item)
        AppLogger.data("Updated task schedule: \(item.id)")
    }

    static func moveToUnscheduled(_ item: PlanItem) {
        updateSchedule(for: item, dueDate: nil, reminderTime: nil)
    }

    static func clearAll(_ items: [PlanItem], in context: ModelContext) throws {
        items.forEach { NotificationService.cancelTaskReminder(for: $0) }
        items.forEach { context.delete($0) }
        try context.save()
        AppLogger.data("Cleared \(items.count) tasks")
    }

    static func delete(_ item: PlanItem, in context: ModelContext) {
        NotificationService.cancelTaskReminder(for: item)
        AppLogger.data("Deleted task: \(item.id)")
        context.delete(item)
    }
}
