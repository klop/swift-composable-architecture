import Combine
import ComposableArchitecture
import XCTest

final class EffectModulationTests: XCTestCase {
  struct EffectId: Hashable {}
  struct TestError: Error {}
  
  var cancellables: Set<AnyCancellable> = []
  
  func test() {
    let effect = Effect<Int, Error>(value: 3).cancellable2(id: EffectId())

    effect
      .sink(receiveCompletion: { print($0) }, receiveValue: { print($0) })
      .store(in: &cancellables)
    
    Effect<Int, Error>(value: 4).cancellable2(id: EffectId()).sink(receiveCompletion: { print($0) }, receiveValue: { print($0) }).store(in: &cancellables)
    Effect<Int, Error>(error: TestError()).cancellable2(id: EffectId()).sink(receiveCompletion: { print($0) }, receiveValue: { print($0) }).store(in: &cancellables)
    Effect<Int, Error>(value: 6).cancellable2(id: EffectId()).sink(receiveCompletion: { print($0) }, receiveValue: { print($0) }).store(in: &cancellables)
    Effect<Int, Error>(value: 7).cancellable2(id: EffectId()).sink(receiveCompletion: { print($0) }, receiveValue: { print($0) }).store(in: &cancellables)
    Effect<Int, Error>(value: 8).cancellable2(id: EffectId()).sink(receiveCompletion: { print($0) }, receiveValue: { print($0) }).store(in: &cancellables)
  }
}
