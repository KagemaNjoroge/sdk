// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// SharedOptions=--enable-experiment=control-flow-collections,spread-collections,constant-update-2018

// Test that a null stream expression procudes a runtime error.
import 'package:async_helper/async_helper.dart';

void main() {
  asyncTest(() async {
    // Null stream.
    Stream<int> nullStream = null;
    asyncExpectThrows<NoSuchMethodError>(
        () async => <int>[await for (var i in nullStream) 1]);
    asyncExpectThrows<NoSuchMethodError>(
        () async => <int, int>{await for (var i in nullStream) 1: 1});
    asyncExpectThrows<NoSuchMethodError>(
        () async => <int>{await for (var i in nullStream) 1});
  });
}
