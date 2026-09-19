import Foundation
import SwiftData

/// 删除的统一出口：确认之后才落库，落库之后留一小段撤销窗口。
///
/// MVP_SCOPE 和 UX_FLOW 都承诺了二次确认，但列表长按菜单里的「删除」是直接
/// `context.delete`，误触一下任务连带提醒就没了；而同一个任务在详情页删除却有
/// confirmationDialog。这里把两种入口收敛成一套行为，并让撤销成为可能。
enum DeletionCoordinator {
    /// 删除前必须先取快照：对象一旦 delete，它的字段就不能再读了。
    static func snapshot(_ item: PlanItem) -> PlanItemBackup { PlanItemBackup(item) }

    static func snapshot(_ note: Note) -> NoteBackup { NoteBackup(note) }

    @discardableResult
    static func delete(_ item: PlanItem, in context: ModelContext) -> Bool {
        PlanItemService.delete(item, in: context)
        return save(context)
    }

    @discardableResult
    static func delete(_ note: Note, in context: ModelContext) -> Bool {
        context.delete(note)
        return save(context)
    }

    @discardableResult
    static func restore(_ snapshot: PlanItemBackup, in context: ModelContext) -> PlanItem {
        let item = snapshot.makePlanItem()
        context.insert(item)
        // 删除时提醒已经被取消，撤销回来就要按原日期重排。
        NotificationService.scheduleTaskReminder(for: item)
        save(context)
        return item
    }

    @discardableResult
    static func restore(_ snapshot: NoteBackup, in context: ModelContext) -> Note {
        let note = snapshot.makeNote()
        context.insert(note)
        save(context)
        return note
    }

    @discardableResult
    private static func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            AppLogger.dataError("删除未能落盘: \(error.localizedDescription)")
            Task { @MainActor in
                GlobalBannerCenter.shared.show(
                    title: "删除没能保存",
                    message: "存储空间可能不可用，请重试一次。",
                    tone: .error
                )
            }
            return false
        }
    }
}
