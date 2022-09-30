// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:async';

import 'package:args/args.dart';

import 'package:vm_service/vm_service.dart';

import 'analysis.dart';
import 'expression.dart';
import 'format.dart';
import 'load.dart';
export 'expression.dart' show Output;

abstract class Command {
  String get name;
  String get description;
  String get usage;
  List<String> get nameAliases => const [];

  final ArgParser argParser = ArgParser();

  Future execute(CliState state, List<String> allArgs) async {
    try {
      int startOfRest = 0;
      while (startOfRest < allArgs.length &&
          allArgs[startOfRest].startsWith('-')) {
        startOfRest++;
      }

      final options = argParser.parse(allArgs.take(startOfRest).toList());
      final args = allArgs.skip(startOfRest).toList();
      await executeInternal(state, options, args);
    } catch (e, s) {
      state.output.print('An error occured: $e\n$s');
      printUsage(state);
    }
  }

  Future executeInternal(CliState state, ArgResults options, List<String> args);

  void printUsage(CliState state) {
    if (nameAliases.isEmpty) {
      state.output.print('Usage for $name:');
    } else {
      state.output
          .print('Usage for $name (aliases: ${nameAliases.join(' ')}):');
    }
    state.output.print('   $usage');
  }
}

abstract class SnapshotCommand extends Command {
  SnapshotCommand();

  Future executeInternal(
      CliState state, ArgResults options, List<String> args) async {
    if (!state.isInitialized) {
      state.output.print('No `*.heapsnapshot` loaded. See `help load`.');
      return;
    }
    await executeSnapshotCommand(state, options, args);
  }

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args);
}

class LoadCommand extends Command {
  final name = 'load';
  final description = 'Loads a *.heapsnapshot produced by the Dart VM.';
  final usage = 'load <file.heapsnapshot>';

  LoadCommand();

  Future executeInternal(
      CliState state, ArgResults options, List<String> args) async {
    HeapSnapshotGraph.getSnapshot;

    if (args.length != 1) {
      printUsage(state);
      return;
    }
    final url = args.single;
    if (url.startsWith('http') || url.startsWith('ws')) {
      try {
        final chunks = await loadFromUri(Uri.parse(url));
        state.initialize(Analysis(HeapSnapshotGraph.fromChunks(chunks)));
        state.output.print('Loaded heapsnapshot from "$url".');
      } catch (e) {
        state.output.print('Could not load heapsnapshot from "$url".');
      }
      return;
    }

    final filename = url.startsWith('~/')
        ? (Platform.environment['HOME']! + url.substring(1))
        : url;
    if (!File(filename).existsSync()) {
      state.output.print('File "$filename" doesn\'t exist.');
      return;
    }
    try {
      final bytes = File(filename).readAsBytesSync();
      state.initialize(
          Analysis(HeapSnapshotGraph.fromChunks([bytes.buffer.asByteData()])));
      state.output.print('Loaded heapsnapshot from "$filename".');
    } catch (e) {
      state.output.print('Could not load heapsnapshot from "$filename".');
      return;
    }
  }
}

class StatsCommand extends SnapshotCommand {
  final name = 'stats';
  final description = 'Calculates statistics about a set of objects.';
  final usage = 'stats [-n/--max=NUM] [-c/--sort-by-count] <expr> ';
  final nameAliases = ['stat'];

  StatsCommand() {
    argParser.addFlag('sort-by-count',
        abbr: 'c',
        help: 'Sorts by count (instead of size).',
        defaultsTo: false);
    argParser.addOption('max',
        abbr: 'n',
        help: 'Limits the number of lines to be printed.',
        defaultsTo: '20');
  }

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    final oids = parseAndEvaluate(
        state.namedSets, state.analysis, args.join(' '), state.output);
    if (oids == null) return;

    final sortByCount = options['sort-by-count'] as bool;
    final lines = int.parse(options['max']!);

    final stats =
        state.analysis.generateObjectStats(oids, sortBySize: !sortByCount);
    state.output.print(formatHeapStats(stats, maxLines: lines));
  }
}

class DataStatsCommand extends SnapshotCommand {
  final name = 'dstats';
  final description =
      'Calculates statistics about the data portion of objects.';
  final usage = 'dstats [-n/--max=NUM] [-c/--sort-by-count] <expr> ';
  final nameAliases = ['dstat'];

  DataStatsCommand() {
    argParser.addFlag('sort-by-count',
        abbr: 'c', help: 'Sort by count', defaultsTo: false);
    argParser.addOption('max',
        abbr: 'n',
        help: 'Limits the number of max to be printed.',
        defaultsTo: '20');
  }

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    final oids = parseAndEvaluate(
        state.namedSets, state.analysis, args.join(' '), state.output);
    if (oids == null) return;

    final sortByCount = options['sort-by-count'] as bool;
    final lines = int.parse(options['max']!);

    final stats =
        state.analysis.generateDataStats(oids, sortBySize: !sortByCount);
    state.output.print(formatDataStats(stats, maxLines: lines));
  }
}

class InfoCommand extends SnapshotCommand {
  final name = 'info';
  final description = 'Prints the known named sets.';
  final usage = 'info';

  InfoCommand();

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    if (args.length != 0) {
      printUsage(state);
      return;
    }

    state.output.print('Known named sets:');
    final table = Table();
    state.namedSets.forEach((String name, Set<int> oids) {
      table.addRow([name, '{#${oids.length}}']);
    });
    state.output.print(indent('  ', table.asString));
  }
}

class ClearCommand extends SnapshotCommand {
  final name = 'clear';
  final description = 'Clears a specific named set (or all).';
  final usage = 'clear <name>*';

  ClearCommand();

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    if (args.isEmpty) {
      state.namedSets.clearWhere((key) => key != 'roots');
      return;
    }

    for (final arg in args) {
      state.namedSets.clear(arg);
      return;
    }
  }
}

class RetainingPathCommand extends SnapshotCommand {
  final name = 'retainers';
  final description = 'Prints information about retaining paths.';
  final usage = 'retainers [-d/--depth=<num>] [-n/--max=NUM] <expr>';
  final nameAliases = ['retain'];

  RetainingPathCommand() {
    argParser.addOption('depth',
        abbr: 'd', help: 'Maximum depth of retaining paths.', defaultsTo: '10');
    argParser.addOption('max',
        abbr: 'n',
        help: 'Limits the number of entries printed.',
        defaultsTo: '3');
  }

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    final oids = parseAndEvaluate(
        state.namedSets, state.analysis, args.join(' '), state.output);
    if (oids == null) return;

    final depth = int.parse(options['depth']!);
    final maxEntries = int.parse(options['max']!);

    final paths = state.analysis.retainingPathsOf(oids, depth);
    for (int i = 0; i < paths.length; ++i) {
      if (maxEntries != -1 && i >= maxEntries) break;
      final path = paths[i];
      state.output.print('There are ${path.count} retaining paths of');
      state.output.print(formatRetainingPath(state.analysis.graph, paths[i]));
      state.output.print('');
    }
  }
}

class ExamineCommand extends SnapshotCommand {
  final name = 'examine';
  final description = 'Examins a set of objects.';
  final usage = 'examine [-n/--max=NUM] <expr>?';
  final nameAliases = ['x'];

  ExamineCommand() {
    argParser.addOption('max',
        abbr: 'n',
        help: 'Limits the number of entries to be examined..',
        defaultsTo: '5');
  }

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    final limit = int.parse(options['max']!);

    final oids = parseAndEvaluate(
        state.namedSets, state.analysis, args.join(' '), state.output);
    if (oids == null) return;
    if (oids.isEmpty) return;

    final it = oids.iterator;
    int i = 0;
    while (it.moveNext()) {
      final oid = it.current;
      final info = state.analysis.examine(oid);
      state.output.print('${info.className}@$oid (${info.libraryUri}) {');
      final table = Table();
      info.fieldValues.forEach((name, value) {
        table.addRow([name, value]);
      });
      state.output.print(indent('  ', table.asString));
      state.output.print('}');
      if (++i >= limit) break;
    }
  }
}

class EvaluateCommand extends SnapshotCommand {
  final name = 'eval';
  final description = 'Evaluates a set expression.';
  final usage = 'eval <expr>\n\n$dslDescription';

  EvaluateCommand();

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    final sexpr = parseExpression(
        args.join(' '), state.output, state.namedSets.names.toSet());
    if (sexpr == null) return null;

    final oids = sexpr.evaluate(state.namedSets, state.analysis, state.output);
    if (oids == null) return null;

    late final String name;
    if (sexpr is SetNameExpression) {
      name = sexpr.name;
    } else {
      name = state.namedSets.nameSet(oids);
    }
    state.output.print(' $name {#${oids.length}}');
  }
}

class DescFilterCommand extends SnapshotCommand {
  final name = 'describe-filter';
  final description = 'Describes what a filter expression will match.';
  final usage = 'describe-filter $dslFilter';
  final nameAliases = ['desc-filter', 'desc'];

  DescFilterCommand();

  Future executeSnapshotCommand(
      CliState state, ArgResults options, List<String> args) async {
    final tfilter = state.analysis.parseTraverseFilter(args);
    if (tfilter == null) return null;

    state.output.print(tfilter.asString(state.analysis.graph));
  }
}

class CommandRunner {
  final Command defaultCommand;
  final Map<String, Command> name2command = {};

  CommandRunner(List<Command> commands, this.defaultCommand) {
    for (final command in commands) {
      name2command[command.name] = command;
      for (final alias in command.nameAliases) {
        name2command[alias] = command;
      }
    }
  }

  Future run(CliState state, List<String> args) async {
    if (args.isEmpty) return;

    final commandName = args.first;
    final command = name2command[commandName];
    if (command != null) {
      await command.execute(state, args.skip(1).toList());
      return;
    }
    if (const ['help', 'h'].contains(commandName)) {
      if (args.length > 1) {
        final helpCommandName = args[1];
        final helpCommand = name2command[helpCommandName];
        if (helpCommand != null) {
          helpCommand.printUsage(state);
          return;
        }
      }
      final table = Table();
      name2command.forEach((name, command) {
        if (name == command.name) {
          table.addRow([command.name, command.description]);
        }
      });
      state.output.print('Available commands:');
      state.output.print(indent('    ', table.asString));
      return;
    }

    await defaultCommand.execute(state, args);
  }
}

class CliState {
  NamedSets? _namedSets;
  Analysis? _analysis;
  Output output;

  CliState(this.output);

  void initialize(Analysis analysis) {
    _analysis = analysis;

    _namedSets = NamedSets();
    _namedSets!.nameSet(analysis.roots, 'roots');
  }

  bool get isInitialized => _analysis != null;

  Analysis get analysis => _analysis!;
  NamedSets get namedSets => _namedSets!;
}

final cliCommandRunner = CommandRunner([
  LoadCommand(),
  StatsCommand(),
  DataStatsCommand(),
  InfoCommand(),
  ClearCommand(),
  RetainingPathCommand(),
  EvaluateCommand(),
  ExamineCommand(),
  DescFilterCommand(),
], EvaluateCommand());
