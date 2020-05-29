import Combine

extension Effect {
  func modulate(
    id: AnyHashable,
    flatten: @escaping (AnyPublisher<Effect<Output, Failure>, Failure>) -> Effect
  ) -> Effect {
    Deferred { () -> AnyPublisher<Output, Failure> in
      if let context = contexts[id] {
        context.send(self)
        return Empty().eraseToAnyPublisher()
      }
      
      let subject = PassthroughSubject<Effect<Output, Failure>, Failure>()
      contexts[id] = SubjectContext(subject: subject)
      
      return flatten(subject.prepend(self).eraseToAnyPublisher())
        .handleEvents(receiveCancel: { contexts[id] = nil })
        .eraseToAnyPublisher()
    }
    .eraseToEffect()
  }
  
  public func cancellable2(id: AnyHashable) -> Effect {
    modulate(id: id) { publisher in
      publisher
        .switchToLatest()
        .eraseToEffect()
    }
  }
  
  public static func cancel2(id: AnyHashable) -> Effect {
    Deferred { () -> Empty<Output, Failure> in
      contexts[id]?.sendEmpty()
      return Empty()
    }
    .eraseToEffect()
  }
  
  public func throttle2<S>(
    id: AnyHashable,
    for interval: S.SchedulerTimeType.Stride,
    scheduler: S,
    latest: Bool
  ) -> Effect where S: Scheduler {
    modulate(id: id) { publisher in
      publisher
        .throttle(for: interval, scheduler: scheduler, latest: latest)
        .switchToLatest()
        .eraseToEffect()
    }
  }
  
  public func debounce2<S>(
    id: AnyHashable,
    for dueTime: S.SchedulerTimeType.Stride,
    scheduler: S
  ) -> Effect where S: Scheduler {
    modulate(id: id) { publisher in
      publisher
        .debounce(for: dueTime, scheduler: scheduler)
        .switchToLatest()
        .eraseToEffect()
    }
  }

  public func maxConcurrent(id: AnyHashable, max: Int) -> Effect {
    modulate(id: id) { publisher in
      publisher
        .flatMap(maxPublishers: .max(max)) { $0 }
        .eraseToEffect()
    }
  }
}

final class SubjectContext {
  private let subject: Any
  private let _sendEmpty: () -> Void
  
  init<Output, Failure>(subject: PassthroughSubject<Effect<Output, Failure>, Failure>) {
    self.subject = subject
    self._sendEmpty = { subject.send(Empty().eraseToEffect()) }
  }
  
  func send<Output, Failure: Error>(_ value: Effect<Output, Failure>) {
    guard let subject = subject as? PassthroughSubject<Effect<Output, Failure>, Failure> else {
      return
    }
    
    subject.send(value)
  }
  
  func sendEmpty() {
    _sendEmpty()
  }
}

var contexts: [AnyHashable: SubjectContext] = [:]
