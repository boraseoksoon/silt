/// Scope.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

final class Scope {
  private var defs = Set<Value>()
  let entry: Continuation
  var continuations: [Continuation] = []

  var definitions: Set<Value> {
    return self.defs
  }

  init(_ entry: Continuation) {
    self.entry = entry
    var queue = [Value]()

    Scope.enqueue(&queue, &self.defs, &self.continuations, entry)

    while !queue.isEmpty {
      let def = queue.removeFirst()
      guard def != entry else {
        continue
      }
      for use in def.users {
        Scope.enqueue(&queue, &self.defs, &self.continuations, use.user)
      }
    }
  }

  func contains(_ val: Value) -> Bool {
    return self.defs.contains(val)
  }

  func dump() {
    var stream = FileHandle.standardOutput
    GIRWriter(stream: &stream).writeSchedule(Schedule(self, .early))
  }

  private static func enqueue(
    _ queue: inout [Value], _ defs: inout Set<Value>,
    _ conts: inout [Continuation], _ val: Value) {
    guard defs.insert(val).inserted else {
      return
    }
    queue.append(val)

    if let continuation = val as? Continuation {
      conts.append(continuation)

      for param in continuation.parameters {
        assert(defs.insert(param).inserted)
        queue.append(param)
      }
    } else if let switchConstr = val as? SwitchConstrOp {
      for succ in switchConstr.successors {
        guard let succ = succ.successor else { continue }

        conts.append(succ)
        queue.append(succ)
      }
    }
  }
}