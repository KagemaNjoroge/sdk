// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:compiler/src/util/testing.dart';

/*spec.class: A1:checkedInstance,checks=[],instance*/
/*prod.class: A1:checks=[],instance*/
class A1 {}

// Constructor calls are always statically invoked, so there is no checks at the
// entry and the `Test1` constructor does not cause any checks.
/*spec.class: B1:checks=[$isA1],instance*/
/*prod.class: B1:checks=[],instance*/
class B1 implements A1 {}

/*class: Test1:checks=[],instance*/
class Test1 {
  A1? x;
  @pragma('dart2js:noInline')
  Test1(this.x);
}

/*class: A2:checks=[],instance*/
class A2 {}

// Constructor bodies are always statically resolved, so there is no checks at
// the entry and the `Test2` constructor body does not cause any checks.
/*class: B2:checks=[],instance*/
class B2 implements A2 {}

/*class: Test2:checks=[],indirectInstance*/
abstract class Test2 {
  @pragma('dart2js:noInline')
  Test2(A2 x) {
    makeLive(x);
  }
}

/*class: Use:checks=[],instance*/
class Use extends Test2 {
  Use.A2() : super(new A2());
  Use.B2() : super(new B2());
}

main() {
  Test1(new A1());
  Test1(new B1());
  Test1(null);

  Use.A2();
  Use.B2();
}
