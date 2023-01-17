// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// SharedOptions=--enable-experiment=class-modifiers

mixin class MixinClass {
  int foo = 0;
}

typedef MixinClassTypeDef = MixinClass;

class A with MixinClassTypeDef {}
