//
//  BoringPomodoro.swift
//  boringNotch
//
//  Created by Mustafa Ramadan on 2/7/2025.
//

import Foundation
import Combine
import Defaults
import AppKit

enum PomodoroPhase {
    case work, shortBreak, longBreak
}

final class BoringPomodoro: ObservableObject {
    static let shared = BoringPomodoro()

    // MARK: - Settings
    @Published public var workMinutes: Int
    @Published private var shortMinutes: Int
    @Published private var longMinutes: Int
    @Published private var cyclesBeforeLong: Int
    @Published private var sneakInterval: Int
    @Published private var sneakDuration: Double

    // MARK: - Timer State
    @Published public private(set) var timeRemaining: Int
    @Published public private(set) var totalMinutesSpent: Int = 0
    @Published public var isRunning = false
    @Published public var isPaused = false
    @Published public var didCompleteCycle = false
    @Published public var currentPhase: PomodoroPhase = .work
    @Published public var hasStarted = false
    
    private var cancellables = Set<AnyCancellable>()
    private var timerCancellable: AnyCancellable?
    private var sneakTimer: Timer?
    private var cycleCount = 0

    private var workDuration: Int { workMinutes * 60 }
    private var shortBreakDuration: Int { shortMinutes * 60 }
    private var longBreakDuration: Int { longMinutes * 60 }

    private init() {
        // load raw defaults into locals first (no self used)
        let work     = Defaults[.pomodoroWorkMinutes]
        let short    = Defaults[.pomodoroShortMinutes]
        let long     = Defaults[.pomodoroLongMinutes]
        let cycles   = Defaults[.pomodoroCyclesBeforeLong]
        let interval = Defaults[.pomodoroSneakInterval]
        let duration = Defaults[.pomodoroSneakDuration]

        workMinutes      = work
        shortMinutes     = short
        longMinutes      = long
        cyclesBeforeLong = cycles
        sneakInterval    = interval
        sneakDuration    = duration

        // compute initial timeRemaining without referencing self
        let initialTime = work * 60
        timeRemaining   = initialTime

        setupBindings()
    }
    
    private func setupBindings() {
        $workMinutes
            .dropFirst()
            .removeDuplicates()
            .sink { Defaults[.pomodoroWorkMinutes] = $0 }
            .store(in: &cancellables)
        
        $shortMinutes
            .removeDuplicates()
            .sink { Defaults[.pomodoroShortMinutes] = $0 }
            .store(in: &cancellables)

        $longMinutes
            .removeDuplicates()
            .sink { Defaults[.pomodoroLongMinutes] = $0 }
            .store(in: &cancellables)

        $cyclesBeforeLong
            .removeDuplicates()
            .sink { Defaults[.pomodoroCyclesBeforeLong] = $0 }
            .store(in: &cancellables)

        $sneakInterval
            .removeDuplicates()
            .sink { Defaults[.pomodoroSneakInterval] = $0 }
            .store(in: &cancellables)

        $sneakDuration
            .removeDuplicates()
            .sink { Defaults[.pomodoroSneakDuration] = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Control Methods

    func toggle() {
        if !isRunning {
            isRunning = true
            isPaused = false
            hasStarted = true
            startSession()
        } else {
            isPaused.toggle()
            if isPaused {
                timerCancellable?.cancel()
            } else {
                startTimer()
            }
        }
    }

    func stop() {
        timerCancellable?.cancel()
        isRunning = false
        isPaused = false
        hasStarted = false
        currentPhase = .work
        timeRemaining = workDuration
        cycleCount = 0
        didCompleteCycle = false
        totalMinutesSpent = 0
        stopSneakCycle()
    }

    private func startSession() {
        if currentPhase == .work && !hasStarted {
            hasStarted = true
        }
        startTimer()
        startSneakCycle()
        showSneakPeekTemporarily()
    }

    private func startTimer() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.timerTick() }
    }

    private func timerTick() {
        guard timeRemaining > 0 else {
            timerCancellable?.cancel()
            advancePhase()
            return
        }
        timeRemaining -= 1
    }
    
    func updateTimeRemaining() {
        if !isRunning && currentPhase == .work {
            timeRemaining = workMinutes * 60
        }
    }

    private func advancePhase() {
        switch currentPhase {
        case .work:
            hasStarted = false
            cycleCount += 1
            if cycleCount == cyclesBeforeLong {
                currentPhase = .longBreak
            } else if cycleCount > cyclesBeforeLong {
                celebrateCompletion()
                return
            } else {
                currentPhase = .shortBreak
            }
        case .shortBreak, .longBreak:
            currentPhase = .work
        }

        timeRemaining = phaseDuration()
        isRunning    = true
        startTimer()
        startSneakCycle()
        showSneakPeekTemporarily()
        playSound()
    }

    private func phaseDuration() -> Int {
        switch currentPhase {
        case .work:       return workDuration
        case .shortBreak: return shortBreakDuration
        case .longBreak:  return longBreakDuration
        }
    }

    private func startSneakCycle() {
        sneakTimer?.invalidate()
        sneakTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(sneakInterval), repeats: true) { [weak self] _ in
            self?.showSneakPeekTemporarily()
        }
    }

    private func stopSneakCycle() {
        sneakTimer?.invalidate()
    }

    private func showSneakPeekTemporarily() {
        DispatchQueue.main.async {
            BoringViewCoordinator.shared.toggleSneakPeek(
                status: true,
                type: .pomodoro,
                duration: TimeInterval(self.sneakDuration),
                value: 0,
                icon: "timer"
            )
        }
    }

    var timeRemainingFormatted: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var phaseText: String {
        switch currentPhase {
        case .shortBreak:
            return "Take a short break!"
        case .longBreak:
            return "Take a long break!"
        case .work:
            if didCompleteCycle {
                return "Focus complete! 🎉 Total: \(totalMinutesSpent) mins"
            } else if hasStarted {
                return "Focus!"
            } else {
                return ""
            }
        }
    }
    
    private func celebrateCompletion() {
        stopSneakCycle()
        totalMinutesSpent = max(1, cycleCount) * workMinutes
        isRunning = false
        hasStarted = false
        didCompleteCycle = true
        NSSound(named: .init("Hero"))?.play()
        showSneakPeekTemporarily()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.stop()
        }
    }

    private func playSound() {
        guard Defaults[.playSoundPomodoro] else { return }
        let soundName: NSSound.Name
        switch currentPhase {
        case .work:       soundName = .init("Glass")
        case .shortBreak: soundName = .init("Funk")
        case .longBreak:  soundName = .init("Submarine")
        }
        NSSound(named: soundName)?.play()
    }
}
