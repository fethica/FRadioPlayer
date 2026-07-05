//
//  StallRecovery.swift
//  FRadioPlayer
//
//  Bounded, cancelable retry ladder for mid-playback stalls.
//  Pure scheduling logic, isolated so it can be unit tested with
//  short intervals; the player wires it to real reload actions.
//

import Foundation

final class StallRecovery {

    /// Delays between recovery attempts. When the ladder is exhausted,
    /// `onExhausted` fires instead of another attempt.
    let intervals: [TimeInterval]

    private let queue: DispatchQueue
    private var pending: DispatchWorkItem?
    private var attemptIndex = 0

    /// Called for each attempt. Return `true` if recovery succeeded
    /// (stops the ladder), `false` to keep climbing.
    var onAttempt: (() -> Bool)?

    /// Called once when every attempt has failed.
    var onExhausted: (() -> Void)?

    private(set) var isActive = false

    init(intervals: [TimeInterval] = [2, 4, 8], queue: DispatchQueue = .main) {
        self.intervals = intervals
        self.queue = queue
    }

    /// Starts the ladder from the first interval. No-op if already active,
    /// so repeated stall signals don't reset the climb.
    func start() {
        guard !isActive else { return }
        isActive = true
        attemptIndex = 0
        scheduleNext()
    }

    /// Cancels any pending attempt and resets the ladder.
    func cancel() {
        pending?.cancel()
        pending = nil
        attemptIndex = 0
        isActive = false
    }

    private func scheduleNext() {
        guard attemptIndex < intervals.count else {
            isActive = false
            onExhausted?()
            return
        }

        let delay = intervals[attemptIndex]
        attemptIndex += 1

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isActive else { return }
            if self.onAttempt?() == true {
                self.cancel()
            } else {
                self.scheduleNext()
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
