import 'dart:async';
import 'dart:io' as io;

import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../base/common.dart';
import '../globals.dart' as globals;
import 'devfs_proxy.dart';

@immutable
class DevConfig {
  const DevConfig({
    this.headers = const <String, String>{},
    this.host = 'localhost',
    this.port = 0,
    this.https,
    this.proxy = const <ProxyConfig>[],
  });

  factory DevConfig.fromYaml(YamlMap yaml) {
    if (yaml['host'] is! String && yaml['host'] != null) {
      throwToolExit('Host must be a String. Found ${yaml['host'].runtimeType}');
    }
    if (yaml['port'] is! int && yaml['port'] != null) {
      throwToolExit('Port must be an int. Found ${yaml['port'].runtimeType}');
    }
    if (yaml['headers'] is! YamlMap && yaml['headers'] != null) {
      throwToolExit('Headers must be a Map. Found ${yaml['headers'].runtimeType}');
    }
    if (yaml['https'] is! YamlMap && yaml['https'] != null) {
      throwToolExit('Https must be a Map. Found ${yaml['https'].runtimeType}');
    }

    final List<ProxyConfig> proxyRules = <ProxyConfig>[];
    if (yaml['proxy'] is YamlMap) {
      (yaml['proxy'] as YamlMap).forEach((dynamic key, dynamic value) {
        if (value is YamlMap) {
          final String keyString = key.toString();
          if (!keyString.endsWith('/')) {
            globals.logger.printWarning(
              "Proxy key '$keyString' does not end with '/'. Ignoring this proxy rule.",
            );
          } else {
            proxyRules.add(ProxyConfig.fromYaml(key.toString(), value));
          }
        }
      });
    }

    final Map<String, String> headers = <String, String>{};
    if (yaml['headers'] is YamlMap) {
      (yaml['headers'] as YamlMap).forEach((dynamic key, dynamic value) {
        headers[key.toString()] = value.toString();
      });
    }

    return DevConfig(
      headers: headers,
      host: yaml['host'] as String?,
      port: yaml['port'] as int?,
      https: yaml['https'] == null ? null : HttpsConfig.fromYaml(yaml['https'] as YamlMap),
      proxy: proxyRules,
    );
  }

  final Map<String, String> headers;
  final String? host;
  final int? port;
  final HttpsConfig? https;
  final List<ProxyConfig> proxy;

  @override
  String toString() {
    return '''
  DevConfig:
  headers: $headers
  host: $host
  port: $port
  https: $https
  proxy: $proxy''';
  }
}

@immutable
class HttpsConfig {
  /// Create a new [HttpsConfig] object.
  const HttpsConfig({required this.certPath, required this.certKeyPath});

  /// Create a [HttpsConfig] from a `https` YAML map.
  factory HttpsConfig.fromYaml(YamlMap yaml) {
    if (yaml['cert-path'] is! String && yaml['cert-path'] != null) {
      throwToolExit('Https cert-path must be a String. Found ${yaml['cert-path'].runtimeType}');
    }
    if (yaml['cert-key-path'] is! String && yaml['cert-key-path'] != null) {
      throwToolExit(
        'Https cert-key-path must be a String. Found ${yaml['cert-key-path'].runtimeType}',
      );
    }
    return HttpsConfig(
      certPath: yaml['cert-path'] as String?,
      certKeyPath: yaml['cert-key-path'] as String?,
    );
  }

  final String? certPath;
  final String? certKeyPath;

  @override
  String toString() {
    return '''
    HttpsConfig:
        certPath: $certPath
        certKeyPath: $certKeyPath''';
  }
}

Future<DevConfig> loadDevConfig({
  String? hostname,
  String? port,
  String? tlsCertPath,
  String? tlsCertKeyPath,
  Map<String, String>? headers,
}) async {
  const String devConfigFilePath = 'web/devconfig.yaml';
  final io.File devConfigFile = globals.fs.file(devConfigFilePath);
  DevConfig fileConfig = const DevConfig();

  if (!devConfigFile.existsSync()) {
    globals.printStatus(
      'No $devConfigFilePath found. Running with default web server configuration.',
    );
  } else {
    try {
      final String devConfigContent = await devConfigFile.readAsString();
      final YamlDocument yamlDoc = loadYamlDocument(devConfigContent);
      final YamlNode contents = yamlDoc.contents;
      if (contents is! YamlMap) {
        throw YamlException(
          'The root of $devConfigFilePath must be a YAML map (e.g., "server:"). '
          'Found a ${contents.runtimeType} instead.',
          contents.span,
        );
      }

      if (!contents.containsKey('server') || contents['server'] is! YamlMap) {
        final SourceSpan span =
            (contents.containsKey('server') && contents['server'] is YamlNode)
                ? (contents['server'] as YamlNode).span
                : contents.span;
        throw YamlException(
          'The "$devConfigFilePath" file is found, but the "server" key is '
          'missing or malformed. It must be a YAML map.',
          span,
        );
      }

      final YamlMap serverYaml = contents['server'] as YamlMap;
      fileConfig = DevConfig.fromYaml(serverYaml);
      globals.printStatus('\nParsed devconfig.yaml:');
      globals.printStatus(fileConfig.toString());
    } on YamlException catch (e) {
      String errorMessage = 'Error: Failed to parse $devConfigFilePath: ${e.message}';
      if (e.span != null) {
        errorMessage += '\n  At line ${e.span!.start.line + 1}, column ${e.span!.start.column + 1}';
        errorMessage += '\n  Problematic text: "${e.span!.text}"';
      }
      globals.printError(errorMessage);
      rethrow;
    } on Exception catch (e) {
      globals.printError('An unexpected error occurred while reading devconfig.yaml: $e');
      globals.printStatus(
        'Reverting to default flutter_tools web server configuration due to unexpected error.',
      );
    }
  }

  return DevConfig(
    host: hostname ?? fileConfig.host,
    port: port != null ? int.tryParse(port) : fileConfig.port,
    https:
        (tlsCertPath != null || tlsCertKeyPath != null || fileConfig.https != null)
            ? HttpsConfig(
              certPath: tlsCertPath ?? fileConfig.https?.certPath,
              certKeyPath: tlsCertKeyPath ?? fileConfig.https?.certKeyPath,
            )
            : null,
    headers: <String, String>{
      ...fileConfig.headers,
      ...?headers,
    },
    proxy: fileConfig.proxy,
  );
}
