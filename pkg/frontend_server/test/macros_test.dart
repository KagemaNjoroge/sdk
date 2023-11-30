// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:_fe_analyzer_shared/src/macros/bootstrap.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/serialization.dart';
import 'package:frontend_server/compute_kernel.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() async {
  group('basic macro', () {
    late String productPlatformDill;
    late Directory tempDir;
    late Uri testMacroUri;
    late File packageConfig;
    late File bootstrapDillFile;

    setUp(() async {
      var binDir = File(Platform.resolvedExecutable).parent;
      productPlatformDill = path.join(binDir.parent.path, 'lib', '_internal',
          'vm_platform_strong_product.dill');
      var systemTempDir = Directory.systemTemp;
      tempDir = systemTempDir.createTempSync('frontendServerTest');
      Directory(path.join(tempDir.path, '.dart_tool')).createSync();

      testMacroUri = Uri.parse('package:test_macro/test_macro.dart');
      var bootstrapContent = bootstrapMacroIsolate(
        {
          testMacroUri.toString(): {
            'TestMacro': [''],
          },
        },
        SerializationMode.byteData,
      );
      var bootstrapFile = File(path.join(tempDir.path, 'bootstrap.dart'))
        ..writeAsStringSync(bootstrapContent);
      packageConfig =
          File(path.join(tempDir.path, '.dart_tool', 'package_config.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync('''
  {
    "configVersion": 2,
    "packages": [
      {
        "name": "test_macro",
        "rootUri": "../",
        "packageUri": "lib/"
      },
      {
        "name": "_fe_analyzer_shared",
        "rootUri": "${Platform.script.resolve('../../_fe_analyzer_shared')}",
        "packageUri": "lib/"
      },
      {
        "name": "meta",
        "rootUri": "${Platform.script.resolve('../../meta')}",
        "packageUri": "lib/"
      }
    ]
  }
  ''');
      var testMacroFile =
          File(path.join(tempDir.path, 'lib', 'test_macro.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync('''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class TestMacro implements ClassDeclarationsMacro {
  const TestMacro();

  @override
  Future<void> buildDeclarationsForClass(
      IntrospectableClassDeclaration clazz, MemberDeclarationBuilder builder) async {
    builder.declareInType(DeclarationCode.fromString('int get x => 0;'));
  }
}
''');

      bootstrapDillFile = File(path.join(tempDir.path, 'bootstrap.dart.dill'));
      var bootstrapResult = await computeKernel([
        '--enable-experiment=macros',
        '--no-summary',
        '--no-summary-only',
        '--target=vm',
        '--dart-sdk-summary=file:$productPlatformDill',
        '--output=${bootstrapDillFile.path}',
        '--source=file:${bootstrapFile.path}',
        '--source=file:${testMacroFile.path}',
        '--packages-file=file:${packageConfig.path}',
      ]);
      expect(bootstrapResult.succeeded, true);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    for (var useIncrementalCompiler in [true, false]) {
      test(
          'can be compiled and applied'
          '${useIncrementalCompiler ? ' with incremental compiler' : ''}',
          () async {
        var applyTestMacroFile =
            File('${tempDir.path}/lib/apply_test_macro.dart')
              ..createSync(recursive: true)
              ..writeAsStringSync('''
import 'package:test_macro/test_macro.dart';

@TestMacro()
class TestClass{}

void main() {
  // Use the declaration created by the macro, so the compile will fail if the
  // macro application fails.
  print(TestClass().x);
}
''');
        var applyTestMacroDill =
            File(path.join(tempDir.path, 'apply_test_macro.dart.dill'));
        var applyTestMacroResult = await computeKernel([
          if (useIncrementalCompiler) '--use-incremental-compiler',
          '--enable-experiment=macros',
          '--no-summary',
          '--no-summary-only',
          '--target=vm',
          '--dart-sdk-summary=file:$productPlatformDill',
          '--output=${applyTestMacroDill.path}',
          '--source=file:${applyTestMacroFile.path}',
          '--packages-file=file:${packageConfig.path}',
          '--enable-experiment=macros',
          '--precompiled-macro-format=kernel',
          '--precompiled-macro',
          'file:${bootstrapDillFile.path};$testMacroUri',
          '--macro-serialization-mode=bytedata',
        ]);
        expect(applyTestMacroResult.succeeded, true);
      });
    }
  });
}
