//
//  RemindersManager.swift
//  boringNotchPlus
//
//  Created by Mustafa Ramadan on 19/7/2025.
//

import EventKit
import SwiftUI
import Defaults

final class RemindersManager: ObservableObject {
    static let shared = RemindersManager()

    @Published var reminders: [EKReminder] = []
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    private let store = EKEventStore()

    @MainActor
    func requestAccess() async {
        if !Defaults[.showReminders] { return }
        
        do {
            let granted = try await store.requestFullAccessToReminders()
            if granted {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await updateSelectedDate(selectedDate)
            } else {
                print("Reminder access denied")
            }
        } catch {
            print("Reminder access error: \(error.localizedDescription)")
        }
    }

    @MainActor
    func fetchReminders(for date: Date? = nil) async {
        // Respect the user’s setting
        if !Defaults[.showReminders] {
            self.reminders = []
            return
        }
        
        let targetDate = date ?? selectedDate

        let predicate = store.predicateForReminders(in: nil)
        var fetched = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        // Retry once if empty (first-time permission issue)
        if fetched.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            fetched = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: reminders ?? [])
                }
            }
        }

        applyFilteredResults(from: fetched, for: targetDate)
    }

    @MainActor
    private func applyFilteredResults(from fetched: [EKReminder], for targetDate: Date) {
        let calendar = Calendar.current

        let filtered = fetched.filter { reminder in
            if reminder.dueDateComponents?.date == nil {
                return !reminder.isCompleted || (reminder.completionDate != nil && calendar.isDate(reminder.completionDate!, inSameDayAs: targetDate))
            }

            if let due = reminder.dueDateComponents?.date,
               calendar.isDate(due, inSameDayAs: targetDate) {
                return true
            }

            if reminder.isCompleted,
               let completed = reminder.completionDate,
               calendar.isDate(completed, inSameDayAs: targetDate) {
                return true
            }

            return false
        }

        let sorted = filtered.sorted {
            // Completed reminders should go last
            if $0.isCompleted != $1.isCompleted {
                return !$0.isCompleted
            }
            
            let a = $0.dueDateComponents?.date ?? .distantFuture
            let b = $1.dueDateComponents?.date ?? .distantFuture
            return a < b
        }

        withAnimation {
            self.reminders = sorted
        }
    }

    @MainActor
    func updateSelectedDate(_ date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        if Defaults[.showReminders] {
               await fetchReminders(for: selectedDate)
           }
    }

    func toggleCompletion(for reminder: EKReminder) {
        reminder.isCompleted.toggle()
        do {
            try store.save(reminder, commit: true)

            DispatchQueue.main.async {
                if let index = self.reminders.firstIndex(where: { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }) {
                    self.reminders[index] = reminder
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task {
                        await self.fetchReminders(for: self.selectedDate)
                    }
                }
            }

        } catch {
            print("Failed to update reminder: \(error.localizedDescription)")
        }
    }

    func isCompletedToday(_ reminder: EKReminder) -> Bool {
        guard reminder.isCompleted else { return false }
        if let completedDate = reminder.completionDate {
            return Calendar.current.isDateInToday(completedDate)
        }
        return false
    }
}
