// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:compiler/src/util/testing.dart';

/*spec.class: Class1:needsArgs*/
class Class1<T> {
  Class1();
}

/*spec.class: Class2:needsArgs*/
class Class2<T> {
  Class2();
}

main() {
  dynamic cls1 = Class1<int>();
  makeLive('${cls1.runtimeType}');
  Class2<int>();
  cls1 = null;
}
