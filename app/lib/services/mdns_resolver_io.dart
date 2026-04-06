import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

DateTime? _mdnsNoRouteCooldownUntil;

bool _looksLikeNoRouteError(Object e) {
  final msg = e.toString().toLowerCase();
  return msg.contains('no route to host') || msg.contains('errno = 65');
}

Future<T?> _runMdnsGuarded<T>(
  Future<T?> Function() fn, {
  required String label,
}) {
  final now = DateTime.now();
  if (_mdnsNoRouteCooldownUntil != null &&
      now.isBefore(_mdnsNoRouteCooldownUntil!)) {
    return Future<T?>.value(null);
  }
  final completer = Completer<T?>();
  runZonedGuarded(
    () async {
      try {
        final out = await fn();
        if (!completer.isCompleted) completer.complete(out);
      } catch (e, st) {
        final noRoute = _looksLikeNoRouteError(e);
        if (noRoute) {
          _mdnsNoRouteCooldownUntil = DateTime.now().add(
            const Duration(seconds: 15),
          );
        } else {
          debugPrint('[mDNS] $label error: $e');
          debugPrint(st.toString());
        }
        if (!completer.isCompleted) completer.complete(null);
      }
    },
    (Object error, StackTrace stack) {
      // Some multicast_dns failures (ex: iOS cellular "No route to host") may be
      // reported here even though our await/timeout flow continues normally.
      // Don't complete the future from here to avoid racing the normal path.
      // Avoid noisy stack traces for common network conditions (cellular / no Wi-Fi).
      final looksLikeNoRoute = _looksLikeNoRouteError(error);
      if (looksLikeNoRoute) {
        _mdnsNoRouteCooldownUntil = DateTime.now().add(
          const Duration(seconds: 15),
        );
      } else {
        debugPrint('[mDNS] $label uncaught: $error');
      }
      if (kDebugMode && !looksLikeNoRoute) {
        debugPrint(stack.toString());
      }
    },
  );
  return completer.future;
}

Future<String?> mdnsResolveHost(
  String host, {
  Duration timeout = const Duration(seconds: 5),
}) {
  return _runMdnsGuarded(() async {
    final fqdn = host.endsWith('.local') ? host : '$host.local';
    final client = MDnsClient();
    try {
      await client.start();
      await for (final IPAddressResourceRecord addr
          in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(fqdn),
              )
              .timeout(timeout, onTimeout: (sink) {})) {
        final ip = addr.address.address;
        if (ip.isNotEmpty) return ip;
      }
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }
    return null;
  }, label: 'resolve');
}

Future<String?> mdnsFindByService({
  String service = '_http._tcp',
  String namePrefix = '',
  String? nameContains,
  Duration timeout = const Duration(seconds: 5),
}) {
  return _runMdnsGuarded(() async {
    final client = MDnsClient();
    try {
      await client.start();
      final instances = <String>{};
      await for (final PtrResourceRecord ptr
          in client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.service('$service.local'),
              )
              .timeout(timeout, onTimeout: (sink) {})) {
        if (ptr.domainName.isNotEmpty) {
          instances.add(ptr.domainName);
        }
      }

      for (final inst in instances) {
        final lower = inst.toLowerCase();
        final prefixLower = namePrefix.toLowerCase();
        final containsOk = nameContains == null
            ? false
            : lower.contains(nameContains.toLowerCase());
        final matchesPrefix = namePrefix.isEmpty
            ? true
            : lower.startsWith(prefixLower);
        if (!(matchesPrefix || containsOk)) {
          continue;
        }

        await for (final SrvResourceRecord srv
            in client
                .lookup<SrvResourceRecord>(ResourceRecordQuery.service(inst))
                .timeout(timeout, onTimeout: (sink) {})) {
          final targetHost = srv.target;
          await for (final IPAddressResourceRecord addr
              in client
                  .lookup<IPAddressResourceRecord>(
                    ResourceRecordQuery.addressIPv4(targetHost),
                  )
                  .timeout(timeout, onTimeout: (sink) {})) {
            final ip = addr.address.address;
            if (ip.isNotEmpty) return ip;
          }
        }
      }
    } finally {
      try {
        client.stop();
      } catch (_) {}
    }
    return null;
  }, label: 'browse');
}
