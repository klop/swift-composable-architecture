import Combine

public struct EffectID: Hashable {
  private let rawValue: AnyHashable
    
  init<Value: Hashable>(_ value: Value) {
    rawValue = value
  }
  
  public static func create(
    _ a: String = #file,
    _ b: Int = #line,
    _ c: Int = #column
  ) -> EffectID {
    EffectID(a + "\(b)\(c)")
  }
}

extension Effect where Failure == Never {
  public func cancellable3(id: EffectID) -> Effect {
    modulate(id: id) { effects in
      effects
        .switchToLatest()
        .eraseToEffect()
    }
  }
  
  public func debounce3<S>(
    id: EffectID,
    for dueTime: S.SchedulerTimeType.Stride,
    scheduler: S
  ) -> Effect where S: Scheduler {
    modulate(id: id) { effects in
      effects
        .debounce(for: dueTime, scheduler: scheduler)
        .switchToLatest()
        .eraseToEffect()
    }
  }
}
