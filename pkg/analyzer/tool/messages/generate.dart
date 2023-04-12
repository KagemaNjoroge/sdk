// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This file contains code to generate scanner and parser message
/// based on the information in pkg/front_end/messages.yaml.
///
/// For each message in messages.yaml that contains an 'index:' field,
/// this tool generates an error with the name specified by the 'analyzerCode:'
/// field and an entry in the fastaAnalyzerErrorList for that generated error.
/// The text in the 'analyzerCode:' field must contain the name of the class
/// containing the error and the name of the error separated by a `.`
/// (e.g. ParserErrorCode.EQUALITY_CANNOT_BE_EQUALITY_OPERAND).
///
/// It is expected that 'pkg/front_end/tool/fasta generate-messages'
/// has already been successfully run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:_fe_analyzer_shared/src/scanner/scanner.dart';
import 'package:analyzer_utilities/package_root.dart' as pkg_root;
import 'package:analyzer_utilities/tools.dart';
import 'package:path/path.dart';

import 'error_code_info.dart';

Future<void> main() async {
  await GeneratedContent.generateAll(analyzerPkgPath, allTargets);

  _SyntacticErrorGenerator()
    ..checkForManualChanges()
    ..printSummary();
}

/// A list of all targets generated by this code generator.
final List<GeneratedContent> allTargets = _analyzerGeneratedFiles();

/// Generates a list of [GeneratedContent] objects describing all the analyzer
/// files that need to be generated.
List<GeneratedContent> _analyzerGeneratedFiles() {
  var classesByFile = <String, List<ErrorClassInfo>>{};
  for (var errorClassInfo in errorClasses) {
    (classesByFile[errorClassInfo.filePath] ??= []).add(errorClassInfo);
  }
  var generatedCodes = <String>[];
  return [
    for (var entry in classesByFile.entries)
      GeneratedFile(entry.key, (String pkgPath) async {
        final codeGenerator =
            _AnalyzerErrorGenerator(entry.value, generatedCodes);
        codeGenerator.generate();
        return codeGenerator.out.toString();
      }),
    GeneratedFile('lib/src/error/error_code_values.g.dart',
        (String pkgPath) async {
      final codeGenerator = _ErrorCodeValuesGenerator(generatedCodes);
      codeGenerator.generate();
      return codeGenerator.out.toString();
    }),
  ];
}

/// Code generator for analyzer error classes.
class _AnalyzerErrorGenerator {
  final List<ErrorClassInfo> errorClasses;

  final List<String> generatedCodes;

  final StringBuffer out = StringBuffer('''
// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// THIS FILE IS GENERATED. DO NOT EDIT.
//
// Instead modify 'pkg/analyzer/messages.yaml' and run
// 'dart run --no-pub pkg/analyzer/tool/messages/generate.dart' to update.

// We allow some snake_case and SCREAMING_SNAKE_CASE identifiers in generated
// code, as they match names declared in the source configuration files.
// ignore_for_file: constant_identifier_names
''');

  _AnalyzerErrorGenerator(this.errorClasses, this.generatedCodes);

  void generate() {
    var imports = {'package:analyzer/error/error.dart'};
    bool shouldGenerateFastaAnalyzerErrorCodes = false;
    for (var errorClass in errorClasses) {
      imports.addAll(errorClass.extraImports);
      if (errorClass.includeCfeMessages) {
        shouldGenerateFastaAnalyzerErrorCodes = true;
      }
      analyzerMessages[errorClass.name]!.forEach((_, errorCodeInfo) {
        if (errorCodeInfo is AliasErrorCodeInfo) {
          imports.add(errorCodeInfo.aliasForFilePath.toPackageAnalyzerUri);
        }
      });
    }
    out.writeln();
    for (var importPath in imports.toList()..sort()) {
      out.writeln("import ${json.encode(importPath)};");
    }
    if (shouldGenerateFastaAnalyzerErrorCodes) {
      out.writeln();
      _generateFastaAnalyzerErrorCodeList();
    }
    for (var errorClass in errorClasses.toList()
      ..sort((a, b) => a.name.compareTo(b.name))) {
      out.writeln();
      out.write('class ${errorClass.name} extends ${errorClass.superclass} {');
      var entries = [
        ...analyzerMessages[errorClass.name]!.entries,
        if (errorClass.includeCfeMessages)
          ...cfeToAnalyzerErrorCodeTables.analyzerCodeToInfo.entries
      ];
      for (var entry in entries..sort((a, b) => a.key.compareTo(b.key))) {
        var errorName = entry.key;
        var errorCodeInfo = entry.value;

        out.writeln();
        out.write(errorCodeInfo.toAnalyzerComments(indent: '  '));
        if (errorCodeInfo is AliasErrorCodeInfo) {
          out.writeln(
              '  static const ${errorCodeInfo.aliasForClass} $errorName =');
          out.writeln('${errorCodeInfo.aliasFor};');
        } else {
          generatedCodes.add('${errorClass.name}.$errorName');
          out.writeln('  static const ${errorClass.name} $errorName =');
          out.writeln(errorCodeInfo.toAnalyzerCode(errorClass.name, errorName));
        }
      }
      out.writeln();
      out.writeln('/// Initialize a newly created error code to have the given '
          '[name].');
      out.writeln(
          'const ${errorClass.name}(String name, String problemMessage, {');
      out.writeln('super.correctionMessage,');
      out.writeln('super.hasPublishedDocs = false,');
      out.writeln('super.isUnresolvedIdentifier = false,');
      out.writeln('String? uniqueName,');
      out.writeln('}) : super(');
      out.writeln('name: name,');
      out.writeln('problemMessage: problemMessage,');
      out.writeln("uniqueName: '${errorClass.name}.\${uniqueName ?? name}',");
      out.writeln(');');
      out.writeln();
      out.writeln('@override');
      out.writeln('ErrorSeverity get errorSeverity => '
          '${errorClass.severityCode};');
      out.writeln();
      out.writeln('@override');
      out.writeln('ErrorType get type => ${errorClass.typeCode};');
      out.writeln('}');
    }
  }

  void _generateFastaAnalyzerErrorCodeList() {
    out.writeln('final fastaAnalyzerErrorCodes = <ErrorCode?>[');
    for (var entry in cfeToAnalyzerErrorCodeTables.indexToInfo) {
      var name = cfeToAnalyzerErrorCodeTables.infoToAnalyzerCode[entry];
      out.writeln('${name == null ? 'null' : 'ParserErrorCode.$name'},');
    }
    out.writeln('];');
  }
}

class _ErrorCodeValuesGenerator {
  final List<String> generatedCodes;

  final StringBuffer out = StringBuffer('''
// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// THIS FILE IS GENERATED. DO NOT EDIT.
//
// Instead modify 'pkg/analyzer/messages.yaml' and run
// 'dart run --no-pub pkg/analyzer/tool/messages/generate.dart' to update.

// We allow some snake_case and SCREAMING_SNAKE_CASE identifiers in generated
// code, as they match names declared in the source configuration files.
// ignore_for_file: constant_identifier_names
''');

  _ErrorCodeValuesGenerator(this.generatedCodes);

  void generate() {
    // The scanner error codes are not yet being generated, so we need to add
    // them to the list explicitly.
    generatedCodes.addAll([
      'ScannerErrorCode.EXPECTED_TOKEN',
      'ScannerErrorCode.ILLEGAL_CHARACTER',
      'ScannerErrorCode.MISSING_DIGIT',
      'ScannerErrorCode.MISSING_HEX_DIGIT',
      'ScannerErrorCode.MISSING_IDENTIFIER',
      'ScannerErrorCode.MISSING_QUOTE',
      'ScannerErrorCode.UNABLE_GET_CONTENT',
      'ScannerErrorCode.UNEXPECTED_DOLLAR_IN_STRING',
      'ScannerErrorCode.UNSUPPORTED_OPERATOR',
      'ScannerErrorCode.UNTERMINATED_MULTI_LINE_COMMENT',
      'ScannerErrorCode.UNTERMINATED_STRING_LITERAL',
      'TodoCode.TODO',
      'TodoCode.FIXME',
      'TodoCode.HACK',
      'TodoCode.UNDONE',
    ]);
    generatedCodes.sort();

    out.writeln();
    out.writeln("import 'package:_fe_analyzer_shared/src/base/errors.dart';");
    out.writeln(
        "import 'package:_fe_analyzer_shared/src/scanner/errors.dart';");
    out.writeln("import 'package:analyzer/src/dart/error/ffi_code.dart';");
    out.writeln("import 'package:analyzer/src/error/codes.dart';");
    out.writeln(
        "import 'package:analyzer/src/generated/parser.dart' show ParserErrorCode;");
    out.writeln(
        "import 'package:analyzer/src/manifest/manifest_warning_code.dart';");
    out.writeln(
        "import 'package:analyzer/src/pubspec/pubspec_warning_code.dart';");
    out.writeln();
    out.writeln('const List<ErrorCode> errorCodeValues = [');
    for (var name in generatedCodes) {
      out.writeln('  $name,');
    }
    out.writeln('];');
  }
}

class _SyntacticErrorGenerator {
  final String errorConverterSource;
  final String parserSource;

  factory _SyntacticErrorGenerator() {
    String frontEndSharedPkgPath =
        normalize(join(pkg_root.packageRoot, '_fe_analyzer_shared'));

    String errorConverterSource = File(join(analyzerPkgPath,
            joinAll(posix.split('lib/src/fasta/error_converter.dart'))))
        .readAsStringSync();
    String parserSource = File(join(frontEndSharedPkgPath,
            joinAll(posix.split('lib/src/parser/parser.dart'))))
        .readAsStringSync();

    return _SyntacticErrorGenerator._(errorConverterSource, parserSource);
  }

  _SyntacticErrorGenerator._(this.errorConverterSource, this.parserSource);

  void checkForManualChanges() {
    // Check for ParserErrorCodes that could be removed from
    // error_converter.dart now that those ParserErrorCodes are auto generated.
    int converterCount = 0;
    for (var errorCode
        in cfeToAnalyzerErrorCodeTables.infoToAnalyzerCode.values) {
      if (errorConverterSource.contains('"$errorCode"')) {
        if (converterCount == 0) {
          print('');
          print('The following ParserErrorCodes could be removed'
              ' from error_converter.dart:');
        }
        print('  $errorCode');
        ++converterCount;
      }
    }
    if (converterCount > 3) {
      print('  $converterCount total');
    }

    // Fail if there are manual changes to be made, but do so
    // in a fire and forget manner so that the files are still generated.
    if (converterCount > 0) {
      print('');
      throw 'Error: missing manual code changes';
    }
  }

  void printSummary() {
    // Build a map of error message to ParserErrorCode
    final messageToName = <String, String>{};
    for (var entry in analyzerMessages['ParserErrorCode']!.entries) {
      String message =
          entry.value.problemMessage.replaceAll(RegExp(r'\{\d+\}'), '');
      messageToName[message] = entry.key;
    }

    String messageFromEntryTemplate(ErrorCodeInfo entry) {
      String problemMessage = entry.problemMessage;
      String message = problemMessage.replaceAll(RegExp(r'#\w+'), '');
      return message;
    }

    // Remove entries that have already been translated
    for (ErrorCodeInfo entry
        in cfeToAnalyzerErrorCodeTables.infoToAnalyzerCode.keys) {
      messageToName.remove(messageFromEntryTemplate(entry));
    }

    // Print the # of autogenerated ParserErrorCodes.
    print('${cfeToAnalyzerErrorCodeTables.infoToAnalyzerCode.length} of '
        '${messageToName.length} ParserErrorCodes generated.');

    // List the ParserErrorCodes that could easily be auto generated
    // but have not been already.
    final analyzerToFasta = <String, List<String>>{};
    frontEndMessages.forEach((fastaName, entry) {
      final analyzerName = messageToName[messageFromEntryTemplate(entry)];
      if (analyzerName != null) {
        analyzerToFasta
            .putIfAbsent(analyzerName, () => <String>[])
            .add(fastaName);
      }
    });
    if (analyzerToFasta.isNotEmpty) {
      print('');
      print('The following ParserErrorCodes could be auto generated:');
      for (String analyzerName in analyzerToFasta.keys.toList()..sort()) {
        List<String> fastaNames = analyzerToFasta[analyzerName]!;
        if (fastaNames.length == 1) {
          print('  $analyzerName = ${fastaNames.first}');
        } else {
          print('  $analyzerName = $fastaNames');
        }
      }
      if (analyzerToFasta.length > 3) {
        print('  ${analyzerToFasta.length} total');
      }
    }

    // List error codes in the parser that have not been translated.
    final untranslatedFastaErrorCodes = <String>{};
    Token token = scanString(parserSource).tokens;
    while (!token.isEof) {
      if (token.isIdentifier) {
        String? fastaErrorCode;
        String lexeme = token.lexeme;
        if (lexeme.length > 7) {
          if (lexeme.startsWith('message')) {
            fastaErrorCode = lexeme.substring(7);
          } else if (lexeme.length > 8) {
            if (lexeme.startsWith('template')) {
              fastaErrorCode = lexeme.substring(8);
            }
          }
        }
        if (fastaErrorCode != null &&
            cfeToAnalyzerErrorCodeTables.frontEndCodeToInfo[fastaErrorCode] ==
                null) {
          untranslatedFastaErrorCodes.add(fastaErrorCode);
        }
      }
      token = token.next!;
    }
    if (untranslatedFastaErrorCodes.isNotEmpty) {
      print('');
      print('The following error codes in the parser are not auto generated:');
      final sorted = untranslatedFastaErrorCodes.toList()..sort();
      for (String fastaErrorCode in sorted) {
        String analyzerCode = '';
        String problemMessage = '';
        var entry = frontEndMessages[fastaErrorCode];
        if (entry != null) {
          // TODO(paulberry): handle multiple analyzer codes
          if (entry.index == null && entry.analyzerCode.length == 1) {
            analyzerCode = entry.analyzerCode.single;
            problemMessage = entry.problemMessage;
          }
        }
        print('  ${fastaErrorCode.padRight(30)} --> $analyzerCode'
            '\n      $problemMessage');
      }
    }
  }
}

extension on String {
  String get toPackageAnalyzerUri =>
      replaceFirst(RegExp('^lib/'), 'package:analyzer/');
}
