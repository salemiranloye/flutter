// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:yaml/yaml.dart';
import '../base/logger.dart';
import '../globals.dart' as globals;

abstract class ProxyRule {
  bool matches(String path);
  Uri getTargetUrl(String path);

  static ProxyRule? fromYaml(YamlMap yaml, {Logger? logger}) {
    if (PrefixProxyRule.canHandle(yaml)) {
      return PrefixProxyRule.fromYaml(yaml, logger: logger);
    } else if (RegexProxyRule.canHandle(yaml)) {
      return RegexProxyRule.fromYaml(yaml, logger: logger);
    } else {
      logger?.printError('Invalid proxy rule in YAML: $yaml');
      return null;
    }
  }
}

class RegexProxyRule implements ProxyRule {
  RegexProxyRule({required RegExp pattern, required String target, String? replacement})
    : _pattern = pattern,
      _target = target,
      _replacement = replacement;

  final RegExp _pattern;
  final String _target;
  final String? _replacement;

  @override
  bool matches(String path) {
    return _pattern.hasMatch(path);
  }

  String _replace(String path) {
    if (_replacement == null) {
      return path;
    }
    return path.replaceAllMapped(_pattern, (Match match) {
      String result = _replacement;
      for (var i = 0; i <= match.groupCount; i++) {
        result = result.replaceAll('\$$i', match.group(i) ?? '');
      }
      return result;
    });
  }

  @override
  Uri getTargetUrl(String path) {
    final Uri targetBaseUri = Uri.parse(_target);
    final String rewrittenRequest = _replace(path);
    return targetBaseUri.resolve(rewrittenRequest);
  }

  @override
  String toString() {
    return '{pattern: ${_pattern.pattern}, target: $_target, replace: ${_replacement ?? 'null'}}';
  }

  static bool canHandle(YamlMap yaml) {
    return yaml.containsKey('regex') &&
        yaml['regex'] is String &&
        (yaml['regex'] as String).isNotEmpty;
  }

  static RegexProxyRule? fromYaml(YamlMap yaml, {Logger? logger}) {
    final regex = yaml['regex'] as String?;
    final target = yaml['target'] as String?;
    final replacement = yaml['replace'] as String?;
    final Logger effectiveLogger = logger ?? globals.logger;
    if (regex == null || regex.isEmpty) {
      return null;
    } else if (target == null || target.isEmpty) {
      effectiveLogger.printError("Invalid 'target' for 'regex': $regex. 'target' cannot be null");
      return null;
    }
    RegExp? pattern;
    try {
      pattern = RegExp(regex.trim());
    } on FormatException catch (e) {
      pattern = RegExp(RegExp.escape(regex));
      effectiveLogger.printWarning(
        "Invalid regex pattern in 'regex': '$regex'. Treating $regex as string. Error: $e",
      );
    }
    return RegexProxyRule(pattern: pattern, target: target, replacement: replacement?.trim());
  }
}

class PrefixProxyRule implements ProxyRule {
  PrefixProxyRule({required String pattern, required String target, String? replacement})
    : _pattern = pattern,
      _target = target,
      _replacement = replacement;

  final String _pattern;
  final String _target;
  final String? _replacement;

  @override
  bool matches(String path) {
    return path.startsWith(_pattern);
  }

  String _replace(String path) {
    if (_replacement == null) {
      return path;
    }
    return path.replaceFirst(_pattern, _replacement);
  }

  @override
  Uri getTargetUrl(String path) {
    final Uri targetBaseUri = Uri.parse(_target);
    final String rewrittenRequest = _replace(path);
    return targetBaseUri.replace(path: rewrittenRequest);
  }

  @override
  String toString() {
    return '{prefix: $_pattern, target: $_target, replace: ${_replacement ?? 'null'}}';
  }

  static bool canHandle(YamlMap yaml) {
    return yaml.containsKey('prefix') &&
        yaml['prefix'] is String &&
        (yaml['prefix'] as String).isNotEmpty;
  }

  static PrefixProxyRule? fromYaml(YamlMap yaml, {Logger? logger}) {
    final pattern = yaml['prefix'] as String?;
    final target = yaml['target'] as String?;
    final replacement = yaml['replace'] as String?;
    final Logger effectiveLogger = logger ?? globals.logger;

    if (pattern == null || pattern.isEmpty) {
      return null;
    } else if (target == null || target.isEmpty) {
      effectiveLogger.printError(
        "Invalid 'target' for 'prefix': $pattern. 'target' cannot be null",
      );
      return null;
    }
    return PrefixProxyRule(pattern: pattern, target: target, replacement: replacement?.trim());
  }
}
