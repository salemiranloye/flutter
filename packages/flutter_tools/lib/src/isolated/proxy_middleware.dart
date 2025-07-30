// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_proxy/shelf_proxy.dart';

import '../globals.dart' as globals;
import '../web/devfs_proxy.dart';

/// Creates a new `shelf.Request` by proxying an `originalRequest` to a `finalTargetUrl`.
/// The new request will have the same method, headers, body, and context as the
/// `originalRequest`, but its URL will be set to `finalTargetUrl`.
///
shelf.Request proxyRequest(shelf.Request originalRequest, Uri finalTargetUrl) {
  return shelf.Request(
    originalRequest.method,
    finalTargetUrl,
    headers: originalRequest.headers,
    body: originalRequest.read(),
    context: originalRequest.context,
  );
}

/// Creates a Shelf [Middleware] that proxies requests based on a list of [ProxyRule]s.
///
/// This middleware iterates through the provided [effectiveProxy] rules for each incoming
/// [shelf.Request]. If a rule's pattern matches the request's path, the request is
/// rewritten and forwarded to the target URI defined in the matching [ProxyRule].
///
/// If a proxy request results in a 404 Not Found status from the target, or if an
/// exception occurs during the proxy attempt, the request is allowed to "fall through"
/// to the next handler in the Shelf stack (the [innerHandler]).
///
shelf.Middleware proxyMiddleware(List<ProxyRule> effectiveProxy) {
  return (shelf.Handler innerHandler) {
    return (shelf.Request request) async {
      String requestPath = request.requestedUri.path;
      for (final rule in effectiveProxy) {
        if (rule.matches(requestPath)) {
          final Uri targetBaseUri = Uri.parse(rule.target);
          final String rewrittenRequest = rule.replace(requestPath);
          final Uri finalTargetUrl = targetBaseUri.resolve(rewrittenRequest);
          try {
            final shelf.Request proxyBackendRequest = proxyRequest(request, finalTargetUrl);
            final shelf.Response proxyResponse = await proxyHandler(targetBaseUri)(
              proxyBackendRequest,
            );
            final isInternalRequest = proxyResponse.headers['sec-fetch-mode'] == 'no-cors';
            if (!internalRequest) {
              globals.logger.printStatus(
                '[PROXY] Matched "$requestPath". Requesting "$finalTargetUrl"',
              );
              globals.logger.printTrace('[PROXY] Matched with proxy rule: $rule');
            }
            if (proxyResponse.statusCode == 404) {
              if (!internalRequest) {
                globals.printTrace('[PROXY] "$finalTargetUrl" responded with status 404');
              }
              return innerHandler(request);
            }
            return proxyResponse;
          } on Exception catch (e) {
            globals.logger.printError(
              '[PROXY] error for $finalTargetUrl: $e. Allowing fall-through.',
            );

            return innerHandler(request);
          }
        }
      }

      return innerHandler(request);
    };
  };
}
