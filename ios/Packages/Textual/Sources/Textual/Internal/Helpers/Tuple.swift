import Foundation

// Finite arity snapshots avoid the iOS 17 parameter-pack runtime.
struct Tuple0: Equatable {
  var values: ()
  static func == (lhs: Self, rhs: Self) -> Bool { true }
}

func Tuple() -> Tuple0 { Tuple0(values: ()) }

struct Tuple1<P0: Equatable>: Equatable {
  var values: P0
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values == rhs.values
  }
}

func Tuple<P0: Equatable>(_ property0: P0) -> Tuple1<P0> {
  Tuple1(values: property0)
}

struct Tuple2<P0: Equatable, P1: Equatable>: Equatable {
  var values: (P0, P1)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1
  }
}

func Tuple<P0: Equatable, P1: Equatable>(_ property0: P0, _ property1: P1) -> Tuple2<P0, P1> {
  Tuple2(values: (property0, property1))
}

struct Tuple3<P0: Equatable, P1: Equatable, P2: Equatable>: Equatable {
  var values: (P0, P1, P2)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1 && lhs.values.2 == rhs.values.2
  }
}

func Tuple<P0: Equatable, P1: Equatable, P2: Equatable>(_ property0: P0, _ property1: P1, _ property2: P2) -> Tuple3<P0, P1, P2> {
  Tuple3(values: (property0, property1, property2))
}

struct Tuple4<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable>: Equatable {
  var values: (P0, P1, P2, P3)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1 && lhs.values.2 == rhs.values.2 && lhs.values.3 == rhs.values.3
  }
}

func Tuple<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3) -> Tuple4<P0, P1, P2, P3> {
  Tuple4(values: (property0, property1, property2, property3))
}

struct Tuple5<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable>: Equatable {
  var values: (P0, P1, P2, P3, P4)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1 && lhs.values.2 == rhs.values.2 && lhs.values.3 == rhs.values.3 && lhs.values.4 == rhs.values.4
  }
}

func Tuple<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4) -> Tuple5<P0, P1, P2, P3, P4> {
  Tuple5(values: (property0, property1, property2, property3, property4))
}

struct Tuple6<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable, P5: Equatable>: Equatable {
  var values: (P0, P1, P2, P3, P4, P5)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1 && lhs.values.2 == rhs.values.2 && lhs.values.3 == rhs.values.3 && lhs.values.4 == rhs.values.4 && lhs.values.5 == rhs.values.5
  }
}

func Tuple<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable, P5: Equatable>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5) -> Tuple6<P0, P1, P2, P3, P4, P5> {
  Tuple6(values: (property0, property1, property2, property3, property4, property5))
}

struct Tuple7<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable, P5: Equatable, P6: Equatable>: Equatable {
  var values: (P0, P1, P2, P3, P4, P5, P6)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1 && lhs.values.2 == rhs.values.2 && lhs.values.3 == rhs.values.3 && lhs.values.4 == rhs.values.4 && lhs.values.5 == rhs.values.5 && lhs.values.6 == rhs.values.6
  }
}

func Tuple<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable, P5: Equatable, P6: Equatable>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6) -> Tuple7<P0, P1, P2, P3, P4, P5, P6> {
  Tuple7(values: (property0, property1, property2, property3, property4, property5, property6))
}

struct Tuple8<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable, P5: Equatable, P6: Equatable, P7: Equatable>: Equatable {
  var values: (P0, P1, P2, P3, P4, P5, P6, P7)
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.values.0 == rhs.values.0 && lhs.values.1 == rhs.values.1 && lhs.values.2 == rhs.values.2 && lhs.values.3 == rhs.values.3 && lhs.values.4 == rhs.values.4 && lhs.values.5 == rhs.values.5 && lhs.values.6 == rhs.values.6 && lhs.values.7 == rhs.values.7
  }
}

func Tuple<P0: Equatable, P1: Equatable, P2: Equatable, P3: Equatable, P4: Equatable, P5: Equatable, P6: Equatable, P7: Equatable>(_ property0: P0, _ property1: P1, _ property2: P2, _ property3: P3, _ property4: P4, _ property5: P5, _ property6: P6, _ property7: P7) -> Tuple8<P0, P1, P2, P3, P4, P5, P6, P7> {
  Tuple8(values: (property0, property1, property2, property3, property4, property5, property6, property7))
}
