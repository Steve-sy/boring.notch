//
//  BoringReminders.swift
//  boringNotchPlus
//
//  Created by Mustafa Ramadan on 19/7/2025.
//

import SwiftUI
import EventKit

struct ReminderListView: View {
    @ObservedObject private var manager = RemindersManager.shared

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            if !manager.reminders.isEmpty {
                Text("Reminders")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom , 3)
            }
            
            ScrollView(showsIndicators: false) {
                HStack(alignment: .top) {
                    VStack(alignment: .trailing, spacing: 5) {
                        ForEach(manager.reminders.indices, id: \.self) { index in
                            let reminder = manager.reminders[index]
                            VStack(alignment: .trailing) {
                                if let date = reminder.dueDateComponents?.date {
                                    Text(date, style: .time)
                                } else {
                                    Text("No time")
                                }
                            }
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .padding(.bottom, 8)
                            .font(.caption2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(manager.reminders.indices, id: \.self) { index in
                            let reminder = manager.reminders[index]
                            HStack(alignment: .top) {
                                VStack(spacing: 5) {
                                    Image(systemName: reminder.isCompleted ? "checkmark.circle" : "circle")
                                        .foregroundColor(reminder.isCompleted ? .green : .gray)
                                        .font(.footnote)
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                manager.toggleCompletion(for: reminder)
                                                NSSound(named: .init("Tink"))?.play()
                                            }
                                        }

                                    Rectangle()
                                        .frame(width: 1)
                                        .foregroundStyle(.gray.opacity(0.5))
                                        .opacity(index == manager.reminders.count - 1 ? 0 : 1)
                                }
                                .padding(.top, 1)

                                Button {
                                    if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(reminder.calendarItemIdentifier)") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Text(reminder.title)
                                        .font(.footnote)
                                        .foregroundStyle(.gray)
                                        .strikethrough(reminder.isCompleted, color: .gray)
                                }
                                .buttonStyle(.plain)

                                Spacer(minLength: 0)
                            }
                            .opacity(reminder.isCompleted ? 0.6 : 1)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}
