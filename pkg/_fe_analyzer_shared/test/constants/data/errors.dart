// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

String method() => 'foo';

const String string0 =
    /*cfe|dart2js.error: Method invocation is not a constant expression.*/
    /*analyzer.error: CompileTimeErrorCode.CONST_EVAL_METHOD_INVOCATION*/ method();

main() {
  print(string0);
}
