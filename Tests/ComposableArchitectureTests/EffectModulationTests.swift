import Combine
@testable import ComposableArchitecture
import XCTest

final class EffectModulationTests: XCTestCase {
  struct CancelToken: Hashable {}
  struct TestError: Error {}
  
  var cancellables: Set<AnyCancellable> = []
  
  override func tearDown() {
    cancellables.removeAll()
  }
  
  func testCancellation() {
    var values: [Int] = []
    
    let subject = PassthroughSubject<Int, Never>()
    let effect = Effect(subject)
      .cancellable2(id: CancelToken())
    
    effect
      .print()
      .sink { values.append($0) }
      .store(in: &self.cancellables)
    
    XCTAssertEqual(values, [])
    subject.send(1)
    XCTAssertEqual(values, [1])
    subject.send(2)
    XCTAssertEqual(values, [1, 2])
    
    _ = Effect<Never, Never>.cancel2(id: CancelToken())
      .print()
      .sink { _ in }
      .store(in: &self.cancellables)
    
    subject.send(3)
    XCTAssertEqual(values, [1, 2])
  }
  
  func testCancelInFlight() {
    var values: [Int] = []
    
    let subject = PassthroughSubject<Int, Never>()
    Effect(subject)
      .cancellable2(id: CancelToken())
      .sink { values.append($0) }
      .store(in: &self.cancellables)
    
    XCTAssertEqual(values, [])
    subject.send(1)
    XCTAssertEqual(values, [1])
    subject.send(2)
    XCTAssertEqual(values, [1, 2])
    
    Effect(subject)
      .cancellable2(id: CancelToken())
      .sink { values.append($0) }
      .store(in: &self.cancellables)
    
    subject.send(3)
    XCTAssertEqual(values, [1, 2, 3])
    subject.send(4)
    XCTAssertEqual(values, [1, 2, 3, 4])
  }
  
  func testCompleteBeforeCancellation() {
    var values: [Int] = []
    
    let subject = PassthroughSubject<Int, Never>()
    let effect = Effect(subject)
      .cancellable2(id: CancelToken())
    
    effect
      .sink { values.append($0) }
      .store(in: &self.cancellables)
    
    subject.send(1)
    XCTAssertEqual(values, [1])
    
    subject.send(completion: .finished)
    XCTAssertEqual(values, [1])
    
    _ = Effect<Never, Never>.cancel2(id: CancelToken())
      .sink { _ in }
      .store(in: &self.cancellables)
    
    XCTAssertEqual(values, [1])
  }
  
  func testCancellationAfterDelay() {
    var value: Int?
    
    Just(1)
      .delay(for: 0.5, scheduler: DispatchQueue.main)
      .eraseToEffect()
      .cancellable2(id: CancelToken())
      .sink { value = $0 }
      .store(in: &self.cancellables)
    
    XCTAssertEqual(value, nil)
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      _ = Effect<Never, Never>.cancel2(id: CancelToken())
        .sink { _ in }
        .store(in: &self.cancellables)
    }
    
    _ = XCTWaiter.wait(for: [self.expectation(description: "")], timeout: 0.1)
    
    XCTAssertEqual(value, nil)
  }
  
  func testCancellationAfterDelay_WithTestScheduler() {
    let scheduler = DispatchQueue.testScheduler
    var value: Int?
    
    Just(1)
      .delay(for: 2, scheduler: scheduler)
      .eraseToEffect()
      .cancellable2(id: CancelToken())
      .sink { value = $0 }
      .store(in: &self.cancellables)
    
    XCTAssertEqual(value, nil)
    
    scheduler.advance(by: 1)
    Effect<Never, Never>.cancel2(id: CancelToken())
      .sink { _ in }
      .store(in: &self.cancellables)
    
    scheduler.run()
    
    XCTAssertEqual(value, nil)
  }
  
  func testDebounce() {
    let scheduler = DispatchQueue.testScheduler
    var values: [Int] = []
    
    func runDebouncedEffect(value: Int) {
      Just(value)
        .eraseToEffect()
        .debounce2(id: CancelToken(), for: 1, scheduler: scheduler)
        .sink { values.append($0) }
        .store(in: &self.cancellables)
    }
    
    runDebouncedEffect(value: 1)
    
    // Nothing emits right away.
    XCTAssertEqual(values, [])
    
    // Waiting half the time also emits nothing
    scheduler.advance(by: 0.5)
    XCTAssertEqual(values, [])
    
    // Run another debounced effect.
    runDebouncedEffect(value: 2)
    
    // Waiting half the time emits nothing because the first debounced effect has been canceled.
    scheduler.advance(by: 0.5)
    XCTAssertEqual(values, [])
    
    // Run another debounced effect.
    runDebouncedEffect(value: 3)
    
    // Waiting half the time emits nothing because the second debounced effect has been canceled.
    scheduler.advance(by: 0.5)
    XCTAssertEqual(values, [])
    
    // Waiting the rest of the time emits the final effect value.
    scheduler.advance(by: 0.5)
    XCTAssertEqual(values, [3])
    
    // Running out the scheduler
    scheduler.run()
    XCTAssertEqual(values, [3])
  }
  
  func testDebounceIsLazy() {
    let scheduler = DispatchQueue.testScheduler
    var values: [Int] = []
    var effectRuns = 0
    
    func runDebouncedEffect(value: Int) {
      
      Deferred { () -> Just<Int> in
        effectRuns += 1
        return Just(value)
      }
      .eraseToEffect()
      .debounce2(id: CancelToken(), for: 1, scheduler: scheduler)
      .sink { values.append($0) }
      .store(in: &self.cancellables)
    }
    
    runDebouncedEffect(value: 1)
    
    XCTAssertEqual(values, [])
    XCTAssertEqual(effectRuns, 0)
    
    scheduler.advance(by: 0.5)
    
    XCTAssertEqual(values, [])
    XCTAssertEqual(effectRuns, 0)
    
    scheduler.advance(by: 0.5)
    
    XCTAssertEqual(values, [1])
    XCTAssertEqual(effectRuns, 1)
  }
  
  func testMaxConcurrent() {
    var values: [Int] = []
    
    func runMaxConcurrentEffect(_ effect: Effect<Int, Never>) {
      effect
        .maxConcurrent(id: CancelToken(), max: 2)
        .sink { values.append($0) }
        .store(in: &self.cancellables)
    }
    
    let a = PassthroughSubject<Int, Never>()
    let b = PassthroughSubject<Int, Never>()
    
    runMaxConcurrentEffect(a.eraseToEffect())
    runMaxConcurrentEffect(b.eraseToEffect())
    runMaxConcurrentEffect(Effect(value: 3))
    
    a.send(1)
    
    XCTAssertEqual(values, [1])
    
    b.send(2)
    
    XCTAssertEqual(values, [1, 2])
    
    b.send(completion: .finished)
    
    // This test fails because the Combine operator doesn't work how I expected it to.
    // https://github.com/CombineCommunity/rxswift-to-combine-cheatsheet/issues/19
    XCTAssertEqual(values, [1, 2, 3])
  }
  
  func testCancellationWithEffectId() {
    var values: [Int] = []
    
    func runCancellableEffect(_ effect: Effect<Int, Never>) {
      effect
        .cancellable3(id: .create())
        .sink { values.append($0) }
        .store(in: &cancellables)
    }
    
    let a = PassthroughSubject<Int, Never>()
    runCancellableEffect(a.eraseToEffect())
    
    a.send(1)
    a.send(2)
    
    XCTAssertEqual(values, [1, 2], "a hasn't been cancelled yet.")
    
    let b = PassthroughSubject<Int, Never>()
    runCancellableEffect(b.eraseToEffect())
    
    a.send(3)
    
    XCTAssertEqual(
      values,
      [1, 2],
      "a should have been cancelled because b was made cancellable with an equivalent Effect ID."
    )
    
    b.send(4)
    
    XCTAssertEqual(values, [1, 2, 4], "b hasn't been cancelled by anything.")
    
    Effect<Int, Never>(value: 5)
      .cancellable3(id: .create())
      .sink { values.append($0) }
      .store(in: &cancellables)
    
    XCTAssertEqual(values, [1, 2, 4, 5])
    
    b.send(6)
    
    XCTAssertEqual(
      values,
      [1, 2, 4, 5, 6],
      "b wasn't cancelled by the new effect since Effect IDs derive their uniqueness from where they're physically located in code."
    )
    
    cancellables.forEach { $0.cancel() }
  }
}
