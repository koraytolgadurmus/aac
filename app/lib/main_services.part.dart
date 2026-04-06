part of 'main.dart';

class ApiService {
  ApiService(this.baseUrl);
  String baseUrl;
  DateTime? _lastUnauthorizedLogAt;

  // SECURITY: Helper to sanitize sensitive data from logs
  static const Set<String> _sensitiveLogKeys = {
    'qrtoken',
    'pairtoken',
    'token',
    'idtoken',
    'refreshtoken',
    'authorization',
    'x-qr-token',
    'x-auth-sig',
    'x-auth-nonce',
    'secret',
    'claimsecret',
    'pass',
    'password',
    'setup_pass',
    'setup_pass_enc',
    'setup_pass_hash',
    'privatekey',
    'private_key',
    'device_private_key',
    'claim_private_key',
  };

  static dynamic _sanitizeDynamicForLog(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        final key = k.toString();
        final keyNorm = key.trim().toLowerCase();
        if (_sensitiveLogKeys.contains(keyNorm)) {
          out[key] = '<redacted>';
        } else {
          out[key] = _sanitizeDynamicForLog(v);
        }
      });
      return out;
    }
    if (value is List) {
      return value.map(_sanitizeDynamicForLog).toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic> _sanitizeForLog(Map<String, dynamic> body) {
    final sanitized = _sanitizeDynamicForLog(body);
    if (sanitized is Map<String, dynamic>) return sanitized;
    return const <String, dynamic>{};
  }

  String? _apSessionToken;
  String? _apSessionNonce;
  String? _pairToken;
  List<int>? _signingPrivD32;
  int _nextSessionTryAtMs = 0;
  String? lastError;
  String? lastErrCode;
  int? lastHttpStatus;
  bool lastDnsFailure = false;
  Future<void> _nonceChain = Future.value();

  Future<T> _withNonceLock<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _nonceChain = _nonceChain.then((_) async {
      try {
        final res = await fn();
        completer.complete(res);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _setLastError(Object e) {
    final s = e.toString();
    final sl = s.toLowerCase();
    lastError = s;
    lastErrCode = null;
    lastHttpStatus = null;
    lastDnsFailure =
        sl.contains('failed host lookup') ||
        sl.contains('nodename nor servname') ||
        sl.contains('errno = 8') ||
        sl.contains('no address associated with hostname') ||
        sl.contains('name or service not known') ||
        sl.contains('temporary failure in name resolution');
  }

  void _clearLastError() {
    lastError = null;
    lastErrCode = null;
    lastHttpStatus = null;
    lastDnsFailure = false;
  }

  void _captureErrorResponse(int statusCode, String bodyText) {
    lastHttpStatus = statusCode;
    final trimmed = bodyText.trim();
    if (trimmed.isEmpty) return;
    String err = '';
    String reason = '';
    try {
      final obj = jsonDecode(trimmed);
      if (obj is Map) {
        err = (obj['err'] ?? obj['error'] ?? '').toString().trim();
        reason = (obj['reason'] ?? obj['message'] ?? obj['msg'] ?? '')
            .toString()
            .trim();
      }
    } catch (_) {
      // ignore: non-JSON error body
    }
    final haystack =
        '${err.toLowerCase()} ${reason.toLowerCase()} ${trimmed.toLowerCase()}';
    if (haystack.contains('owner required') ||
        haystack.contains('owner_required') ||
        haystack.contains('not owner') ||
        haystack.contains('not_owner') ||
        haystack.contains('unclaimed')) {
      lastErrCode = 'owner_required';
      lastError = reason.isNotEmpty ? reason : err;
      return;
    }
    if (err.isNotEmpty) {
      lastErrCode = err;
      // Keep lastError aligned with the semantic error code for callers.
      lastError = reason.isNotEmpty ? '$err: $reason' : err;
      return;
    }
    if (reason.isNotEmpty) {
      lastError = reason;
      return;
    }
    lastError = 'http_$statusCode';
  }

  void setSigningKey(List<int>? privD32) {
    _signingPrivD32 = (privD32 != null && privD32.isNotEmpty) ? privD32 : null;
  }

  bool get hasSigningKey =>
      _signingPrivD32 != null && _signingPrivD32!.isNotEmpty;
  List<int>? get signingPrivD32 => _signingPrivD32;

  void setPairToken(String? token) {
    final trimmed = token?.trim();
    final changed = (_pairToken ?? '') != (trimmed ?? '');
    if (trimmed == null || trimmed.isEmpty) {
      _pairToken = null;
      if (changed) {
        clearLocalSession();
      }
      return;
    }
    _pairToken = trimmed;
    if (changed) {
      clearLocalSession();
    }
  }

  String? get pairToken => _pairToken;

  void setApSessionToken(String? token) {
    _apSessionToken = (token != null && token.isNotEmpty) ? token : null;
  }

  void setApSessionNonce(String? nonce) {
    _apSessionNonce = (nonce != null && nonce.isNotEmpty) ? nonce : null;
  }

  void clearLocalSession() {
    _apSessionToken = null;
    _apSessionNonce = null;
    _nextSessionTryAtMs = 0;
  }

  void resetAuthBackoff() {
    _nextSessionTryAtMs = 0;
    _nextSignNonceTryAtMs = 0;
    _lastSignFailReason = null;
  }

  Map<String, String> authHeaders({bool json = false}) {
    final headers = <String, String>{};
    headers['User-Agent'] = 'AACApp';
    if (json) headers['Content-Type'] = 'application/json';
    // SoftAP recovery session token (required by firmware for AP endpoints).
    if (_apSessionToken != null && _apSessionToken!.isNotEmpty) {
      headers['X-Session-Token'] = _apSessionToken!;
    }
    if (_apSessionNonce != null && _apSessionNonce!.isNotEmpty) {
      headers['X-Session-Nonce'] = _apSessionNonce!;
    }
    if (_pairToken != null && _pairToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_pairToken';
      // Some platforms/proxies can strip Authorization; keep a dedicated header too.
      headers['X-QR-Token'] = _pairToken!;
    }
    return headers;
  }

  String? _lastSignFailReason;
  int _nextSignNonceTryAtMs = 0;

  bool _hasAuthMaterial() {
    return (_pairToken != null && _pairToken!.isNotEmpty) ||
        (_apSessionToken != null && _apSessionToken!.isNotEmpty) ||
        (_apSessionNonce != null && _apSessionNonce!.isNotEmpty);
  }

  Future<Map<String, String>?> _signedHeaders(
    String method,
    String path,
    String body, {
    bool jsonHeader = true,
  }) async {
    if (!hasSigningKey) {
      _lastSignFailReason = 'missing_signing_key';
      return null;
    }
    return _withNonceLock(() async {
      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (_nextSignNonceTryAtMs != 0 && nowMs < _nextSignNonceTryAtMs) {
          _lastSignFailReason = 'nonce_cooldown';
          return authHeaders(json: jsonHeader);
        }
        final nonceResp = await http
            .get(_u('/api/nonce'), headers: authHeaders())
            .timeout(const Duration(seconds: 5));
        if (nonceResp.statusCode == 429) {
          var retryMs = 1500;
          try {
            final obj = jsonDecode(nonceResp.body);
            if (obj is Map) {
              final parsed = int.tryParse((obj['retryMs'] ?? '').toString());
              if (parsed != null && parsed > 0) retryMs = parsed;
            }
          } catch (_) {}
          _nextSignNonceTryAtMs =
              DateTime.now().millisecondsSinceEpoch + retryMs;
          _lastSignFailReason = 'nonce_http_429';
          return authHeaders(json: jsonHeader);
        }
        if (nonceResp.statusCode < 200 || nonceResp.statusCode >= 300) {
          _nextSignNonceTryAtMs = DateTime.now().millisecondsSinceEpoch + 1500;
          _lastSignFailReason = 'nonce_http_${nonceResp.statusCode}';
          return authHeaders(json: jsonHeader);
        }
        final obj = jsonDecode(nonceResp.body);
        if (obj is! Map) {
          _lastSignFailReason = 'nonce_invalid_json';
          return authHeaders(json: jsonHeader);
        }
        final nonce = (obj['nonce'] ?? '').toString().trim();
        if (nonce.isEmpty) {
          _lastSignFailReason = 'nonce_empty';
          return authHeaders(json: jsonHeader);
        }
        final owned = obj['owned'] == true;
        if (!owned) {
          // Unowned/settling devices can reject signed owner headers.
          _nextSignNonceTryAtMs = DateTime.now().millisecondsSinceEpoch + 5000;
          _lastSignFailReason = 'nonce_unowned_skip_sign';
          return authHeaders(json: jsonHeader);
        }

        final bodySha = sha256.convert(utf8.encode(body)).toString();
        final msg = '$nonce|$method|$path|$bodySha';
        final sig = _ecdsaSignBytesP256(
          privD32: _signingPrivD32!,
          msgBytes: utf8.encode(msg),
        );

        final headers = authHeaders(json: jsonHeader);
        headers['X-Auth-Nonce'] = nonce;
        headers['X-Auth-Sig'] = base64Encode(sig);
        _nextSignNonceTryAtMs = 0;
        _lastSignFailReason = null;
        if (kDebugMode) {
          debugPrint(
            '[AUTH][HTTP] signed headers ok path=$path nonceLen=${nonce.length} sigLen=${sig.length}',
          );
        }
        return headers;
      } catch (e) {
        _nextSignNonceTryAtMs = DateTime.now().millisecondsSinceEpoch + 1500;
        _lastSignFailReason = 'sign_exception';
        if (kDebugMode) {
          debugPrint('[AUTH] signed headers failed: $e');
        }
        return authHeaders(json: jsonHeader);
      }
    });
  }

  Future<bool> ensureOwnerSession() async {
    // Owned devices require an authenticated session for owner-only HTTP ops.
    return _ensureLocalSession();
  }

  // Normalize common typos and ensure a valid scheme so that we never build
  // things like "http://htt//192.168.x.x".
  String _sanitizeBase(String b) {
    if (b.isEmpty) return b;

    String s = b.trim();

    // Remove surrounding quotes if any
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1);
    }

    // Common scheme typos
    s = s.replaceFirst(RegExp(r'^htt//', caseSensitive: false), 'http://');
    s = s.replaceFirst(
      RegExp(r'^http:/(?=[^/])', caseSensitive: false),
      'http://',
    );
    s = s.replaceFirst(
      RegExp(r'^https:/(?=[^/])', caseSensitive: false),
      'https://',
    );
    s = s.replaceFirst(RegExp(r'^http//', caseSensitive: false), 'http://');
    s = s.replaceFirst(RegExp(r'^https//', caseSensitive: false), 'https://');

    // If it still lacks a scheme, add http://
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://' + s;
    }

    // Collapse any accidental triple slashes after the scheme
    s = s.replaceFirst(RegExp(r'^(https?://)/+'), r'$1');

    // Remove single trailing slash so that path join below is clean
    if (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }

    final parsed = Uri.tryParse(s);
    if (parsed != null && parsed.host.isNotEmpty) {
      var host = parsed.host.replaceAll(RegExp(r'\.+$'), '');
      // Common typo: ".loca" instead of ".local"
      if (host.endsWith('.loca') && !host.endsWith('.local')) {
        host = '${host}l';
      }
      if (host == '0.0.0.0') {
        host = '';
      }
      final ipv4Re = RegExp(r'^\d+(\.\d+){3}$');
      final numericRe = RegExp(r'^\d+(\.\d+){2}$');
      if (host.isNotEmpty &&
          !ipv4Re.hasMatch(host) &&
          numericRe.hasMatch(host)) {
        // Likely truncated IPv4 such as "192.168.3"
        host = '';
      }
      if (host.isNotEmpty) {
        final scheme = parsed.scheme.isNotEmpty ? parsed.scheme : 'http';
        final port = (parsed.hasPort && parsed.port != 80 && parsed.port != 443)
            ? ':${parsed.port}'
            : '';
        var path = parsed.path;
        if (path.isEmpty || path == '/') path = '';
        final query = parsed.hasQuery ? '?${parsed.query}' : '';
        final fragment = parsed.hasFragment ? '#${parsed.fragment}' : '';
        s = '$scheme://$host$port$path$query$fragment';
      }
    }
    return s;
  }

  Uri _u(String p) {
    String b = _sanitizeBase(baseUrl);
    final s = p.startsWith('/') ? p : '/$p';
    final full = b + s;
    return Uri.parse(full);
  }

  Map<String, dynamic>? _decodeJsonMapLenient(String body, {String? path}) {
    final raw = body.trim();
    if (raw.isEmpty) return <String, dynamic>{};

    dynamic tryDecode(String input) {
      try {
        return jsonDecode(input);
      } catch (_) {
        return null;
      }
    }

    final direct = tryDecode(raw);
    if (direct is Map<String, dynamic>) return direct;

    final start = raw.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < raw.length; i++) {
      final ch = raw.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == 0x5C) {
          escaped = true;
        } else if (ch == 0x22) {
          inString = false;
        }
        continue;
      }
      if (ch == 0x22) {
        inString = true;
        continue;
      }
      if (ch == 0x7B) {
        depth++;
        continue;
      }
      if (ch == 0x7D) {
        depth--;
        if (depth == 0) {
          final candidate = raw.substring(start, i + 1);
          final parsed = tryDecode(candidate);
          if (parsed is Map<String, dynamic>) {
            if (kDebugMode && candidate.length != raw.length) {
              debugPrint(
                '[API] Lenient JSON recovery path=${path ?? "-"} '
                'rawLen=${raw.length} usedLen=${candidate.length}',
              );
            }
            return parsed;
          }
          return null;
        }
      }
    }

    // Truncated payload recovery: if JSON starts but ends prematurely,
    // try to close open string/braces and decode once more.
    if (depth > 0) {
      final sb = StringBuffer(raw.substring(start));
      if (inString) {
        sb.write('"');
      }
      for (var i = 0; i < depth; i++) {
        sb.write('}');
      }
      final recovered = tryDecode(sb.toString());
      if (recovered is Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint(
            '[API] Lenient truncated JSON recovery path=${path ?? "-"} rawLen=${raw.length}',
          );
        }
        return recovered;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(
    List<String> paths, {
    bool retryWithSession = true,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    for (final p in paths) {
      try {
        // Prefer signed GETs when we have an owner key to avoid 401 flapping.
        if (hasSigningKey) {
          final signed = await _signedHeaders('GET', p, '');
          if (signed != null) {
            final rs = await http.get(_u(p), headers: signed).timeout(timeout);
            if (rs.statusCode >= 200 && rs.statusCode < 300) {
              _clearLastError();
              if (kDebugMode) {
                debugPrint(
                  '[API] GET ${_u(p)} -> 200 len=${rs.body.length} (body hidden)',
                );
              }
              final obj = _decodeJsonMapLenient(rs.body, path: p);
              if (obj != null) return obj;
            }
          } else if (!_hasAuthMaterial()) {
            if (kDebugMode) {
              debugPrint(
                '[AUTH][HTTP] signed headers missing; skip unsigned GET path=$p reason=${_lastSignFailReason ?? 'unknown'}',
              );
            }
            continue;
          }
        }
        final r = await http
            .get(_u(p), headers: authHeaders())
            .timeout(timeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          _clearLastError();
          if (kDebugMode) {
            debugPrint(
              '[API] GET ${_u(p)} -> 200 len=${r.body.length} (body hidden)',
            );
          }
          final obj = _decodeJsonMapLenient(r.body, path: p);
          if (obj != null) return obj;
        } else if (r.statusCode == 401 || r.statusCode == 403) {
          if (retryWithSession) {
            final opened = await _ensureLocalSession();
            if (opened) {
              return _getJson(paths, retryWithSession: false);
            }
          }
          lastHttpStatus = r.statusCode;
          lastErrCode = 'unauthorized';
          lastError = 'unauthorized';
          lastDnsFailure = false;
          if (kDebugMode) {
            final now = DateTime.now();
            if (_lastUnauthorizedLogAt == null ||
                now.difference(_lastUnauthorizedLogAt!) >
                    const Duration(seconds: 2)) {
              _lastUnauthorizedLogAt = now;
              debugPrint('[API] GET ' + _u(p).toString() + ' unauthorized');
            }
          }
          return <String, dynamic>{'ok': false, 'unauthorized': true};
        }
      } catch (e) {
        _setLastError(e);
        if (kDebugMode) {
          debugPrint(
            '[API] GET ' + _u(p).toString() + ' error: ' + e.toString(),
          );
        }
      }
    }
    return null;
  }

  bool _isSoftApBase() {
    try {
      final u = Uri.tryParse(_sanitizeBase(baseUrl));
      return u != null && u.host == '192.168.4.1';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureLocalSession() async {
    // If a session is already set, keep using it. We'll refresh on 401.
    if (_apSessionToken != null &&
        _apSessionToken!.isNotEmpty &&
        _apSessionNonce != null &&
        _apSessionNonce!.isNotEmpty) {
      return true;
    }

    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    if (_nextSessionTryAtMs != 0 && nowEpochMs < _nextSessionTryAtMs) {
      return false;
    }

    return _withNonceLock(() async {
      // Another call may have opened a session while we waited.
      if (_apSessionToken != null &&
          _apSessionToken!.isNotEmpty &&
          _apSessionNonce != null &&
          _apSessionNonce!.isNotEmpty) {
        return true;
      }

      final bearer = _pairToken;
      final hasPair = bearer != null && bearer.isNotEmpty;
      try {
        // 1) Fetch nonce
        final nonceResp = await http
            .get(_u('/api/nonce'), headers: authHeaders())
            .timeout(const Duration(seconds: 5));
        if (nonceResp.statusCode == 429) {
          try {
            final obj = jsonDecode(nonceResp.body);
            if (obj is Map) {
              final retryMs = int.tryParse((obj['retryMs'] ?? '').toString());
              if (retryMs != null && retryMs > 0) {
                _nextSessionTryAtMs =
                    DateTime.now().millisecondsSinceEpoch + retryMs;
              }
            }
          } catch (_) {}
          return false;
        }
        if (nonceResp.statusCode < 200 || nonceResp.statusCode >= 300) {
          _nextSessionTryAtMs = DateTime.now().millisecondsSinceEpoch + 3000;
          return false;
        }
        final nonceObj = jsonDecode(nonceResp.body);
        if (nonceObj is! Map) return false;
        final nonce = (nonceObj['nonce'] ?? '').toString().trim();
        final owned = nonceObj['owned'] == true;
        if (nonce.isEmpty) return false;

        // Owned devices require an ECDSA signing key (even on SoftAP).
        // Unowned devices require the QR pairToken.
        if (owned) {
          if (_signingPrivD32 == null || _signingPrivD32!.isEmpty) return false;
        } else if (!hasPair) {
          return false;
        } else {
          // Unowned flow: pair token exists. Open a real AP session too.
          // Returning `true` without opening a session causes repeated 401 loops
          // on firmwares/endpoints that require X-Session-* headers for /api/status.
        }

        // 2) Open session
        const path = '/api/session/open';
        final body = jsonEncode({'ttl': 180});
        final bodySha = sha256.convert(utf8.encode(body)).toString();

        final headers = authHeaders(json: true);
        if (owned) {
          final priv = _signingPrivD32;
          if (priv == null || priv.isEmpty) {
            debugPrint('[SESSION] Owned device but no signing key');
            return false;
          }
          final msg = '$nonce|POST|$path|$bodySha';
          final sig = _ecdsaSignBytesP256(
            privD32: priv,
            msgBytes: utf8.encode(msg),
          );
          headers['X-Auth-Nonce'] = nonce;
          headers['X-Auth-Sig'] = base64Encode(sig);
          // ✅ QR token da ekle (ESP32'de zorunlu)
          if (_pairToken != null && _pairToken!.isNotEmpty) {
            headers['X-QR-Token'] = _pairToken!;
          }
        } else {
          // ✅ Unowned device'lar için: Authorization Bearer token zaten authHeaders() içinde ekleniyor
          // Ama debug için kontrol edelim
          if (!hasPair) {
            debugPrint('[SESSION] Unowned device but no pairToken');
            return false;
          }
          debugPrint(
            '[SESSION] Unowned device, using Authorization Bearer token',
          );
        }

        final r = await http
            .post(_u(path), headers: headers, body: body)
            .timeout(kLocalHttpRequestTimeout);
        if (r.statusCode == 429) {
          try {
            final obj = jsonDecode(r.body);
            if (obj is Map) {
              final retryMs = int.tryParse((obj['retryMs'] ?? '').toString());
              if (retryMs != null && retryMs > 0) {
                _nextSessionTryAtMs =
                    DateTime.now().millisecondsSinceEpoch + retryMs;
              }
            }
          } catch (_) {}
          debugPrint(
            '[SESSION] Session open rate-limited, retryAt=$_nextSessionTryAtMs',
          );
          return false;
        }
        if (r.statusCode < 200 || r.statusCode >= 300) {
          _nextSessionTryAtMs = DateTime.now().millisecondsSinceEpoch + 3000;
          debugPrint(
            '[SESSION] Session open failed: status=${r.statusCode}, body=${r.body}',
          );
          return false;
        }
        final obj = jsonDecode(r.body);
        if (obj is! Map) return false;
        final tok = (obj['token'] ?? '').toString().trim();
        final non = (obj['nonce'] ?? '').toString().trim();
        if (tok.isEmpty || non.isEmpty) return false;
        _apSessionToken = tok;
        _apSessionNonce = non;
        _nextSessionTryAtMs = 0;
        return true;
      } catch (_) {
        _nextSessionTryAtMs = DateTime.now().millisecondsSinceEpoch + 3000;
        return false;
      }
    });
  }

  Future<Map<String, dynamic>?> _postJsonSingle(
    String path,
    Map<String, dynamic> body,
  ) async {
    final bodyJson = jsonEncode(body);
    try {
      // Prefer signed POSTs when we have an owner key to avoid 401 flapping.
      if (hasSigningKey) {
        final signed = await _signedHeaders('POST', path, bodyJson);
        if (signed != null) {
          final rs = await http
              .post(_u(path), headers: signed, body: bodyJson)
              .timeout(kLocalHttpRequestTimeout);
          if (rs.statusCode >= 200 && rs.statusCode < 300) {
            _clearLastError();
            if (rs.body.isEmpty) return <String, dynamic>{'ok': true};
            final obj = jsonDecode(rs.body);
            if (obj is Map<String, dynamic>) return obj;
            return <String, dynamic>{'ok': true, 'body': obj};
          }
          _captureErrorResponse(rs.statusCode, rs.body);
        } else if (!_hasAuthMaterial()) {
          if (kDebugMode) {
            debugPrint(
              '[AUTH][HTTP] signed headers missing; skip unsigned POST path=$path reason=${_lastSignFailReason ?? 'unknown'}',
            );
          }
          return null;
        }
      }
      final r = await http
          .post(_u(path), headers: authHeaders(json: true), body: bodyJson)
          .timeout(kLocalHttpRequestTimeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _clearLastError();
        if (r.body.isEmpty) return <String, dynamic>{'ok': true};
        final obj = jsonDecode(r.body);
        if (obj is Map<String, dynamic>) return obj;
        return <String, dynamic>{'ok': true, 'body': obj};
      }
      _captureErrorResponse(r.statusCode, r.body);
      if (r.statusCode == 401 || r.statusCode == 403) {
        // Try signed request (owner key) before opening a session.
        final signed = await _signedHeaders('POST', path, bodyJson);
        if (signed != null) {
          final rs = await http
              .post(_u(path), headers: signed, body: bodyJson)
              .timeout(kLocalHttpRequestTimeout);
          if (rs.statusCode >= 200 && rs.statusCode < 300) {
            _clearLastError();
            if (rs.body.isEmpty) return <String, dynamic>{'ok': true};
            final obj = jsonDecode(rs.body);
            if (obj is Map<String, dynamic>) return obj;
            return <String, dynamic>{'ok': true, 'body': obj};
          }
          _captureErrorResponse(rs.statusCode, rs.body);
        }
        final opened = await _ensureLocalSession();
        if (opened) {
          final r2 = await http
              .post(_u(path), headers: authHeaders(json: true), body: bodyJson)
              .timeout(kLocalHttpRequestTimeout);
          if (r2.statusCode >= 200 && r2.statusCode < 300) {
            _clearLastError();
            if (r2.body.isEmpty) return <String, dynamic>{'ok': true};
            final obj = jsonDecode(r2.body);
            if (obj is Map<String, dynamic>) return obj;
            return <String, dynamic>{'ok': true, 'body': obj};
          }
          _captureErrorResponse(r2.statusCode, r2.body);
        }
      }
    } catch (e) {
      _setLastError(e);
      if (kDebugMode) {
        debugPrint(
          '[API] POST ' + _u(path).toString() + ' error: ' + e.toString(),
        );
      }
    }
    return null;
  }

  Future<DeviceState?> fetchState() async {
    final j = await _getJson(['/api/status', '/state']);
    if (j == null || j['unauthorized'] == true) return null;
    final core = _extractStateCore(j);
    return DeviceState.fromJson(core);
  }

  Future<Map<String, dynamic>?> fetchHistory() async {
    final j = await _getJson(['/api/history']);
    if (j == null || j['unauthorized'] == true) return null;
    return j;
  }

  Future<bool> sendCommand(Map<String, dynamic> body) async {
    // En olası endpoint'leri öne al. (Eski fw'ler farklı path'ler kullanabiliyor.)
    final endpoints = ['/api/cmd', '/cmd', '/api/control', '/command'];
    for (final p in endpoints) {
      final j = await _postJsonSingle(p, body);
      if (j == null) continue;
      if (j['ok'] == true) return true;
      if (j.containsKey('state') || j.containsKey('fw')) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> uploadLocalOta({
    required Uint8List firmwareBytes,
    required String sha256Hex,
    String fileName = 'firmware.bin',
    Duration timeout = const Duration(seconds: 180),
  }) async {
    const path = '/api/ota/local';
    if (firmwareBytes.isEmpty) {
      return <String, dynamic>{'ok': false, 'err': 'empty_firmware'};
    }
    final expectedSha = sha256Hex.trim().toLowerCase();
    if (expectedSha.length != 64) {
      return <String, dynamic>{'ok': false, 'err': 'bad_sha256'};
    }
    final actualSha = sha256.convert(firmwareBytes).toString().toLowerCase();
    if (actualSha != expectedSha) {
      return <String, dynamic>{
        'ok': false,
        'err': 'sha256_mismatch_local',
        'sha256': actualSha,
      };
    }

    final signed = await _signedHeaders('POST', path, '', jsonHeader: false);
    if (signed == null) {
      return <String, dynamic>{
        'ok': false,
        'err': _lastSignFailReason ?? 'sign_required',
      };
    }
    signed['X-FW-SHA256'] = expectedSha;

    try {
      final req = http.MultipartRequest('POST', _u(path));
      req.headers.addAll(signed);
      req.files.add(
        http.MultipartFile.fromBytes(
          'firmware',
          firmwareBytes,
          filename: fileName,
        ),
      );
      final streamed = await req.send().timeout(timeout);
      final bodyText = await streamed.stream.bytesToString();
      if (bodyText.isNotEmpty) {
        try {
          final obj = jsonDecode(bodyText);
          if (obj is Map<String, dynamic>) {
            if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
              return obj;
            }
            return <String, dynamic>{
              'ok': false,
              'status': streamed.statusCode,
              ...obj,
            };
          }
        } catch (_) {}
      }
      return <String, dynamic>{
        'ok': streamed.statusCode >= 200 && streamed.statusCode < 300,
        'status': streamed.statusCode,
      };
    } catch (e) {
      _setLastError(e);
      return <String, dynamic>{'ok': false, 'err': e.toString()};
    }
  }

  Future<bool> joinInviteLocal(Map<String, dynamic> invitePayload) async {
    // /join endpoint does not require auth; it validates the invite signature.
    final endpoints = ['/join', '/api/join'];
    final body = jsonEncode(invitePayload);
    for (final ep in endpoints) {
      final url = _u(ep);
      try {
        final r = await http
            .post(
              url,
              headers: const {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(kLocalHttpRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) return true;
        final bodyPreview = r.body.length > 200
            ? r.body.substring(0, 200) + '...'
            : r.body;
        debugPrint(
          '[JOIN][AP] http status=${r.statusCode} path=$ep body=$bodyPreview',
        );
        if (r.statusCode == 404 && r.body.isEmpty) {
          // Probe AP portal if available.
          await _getJson(['/info'], retryWithSession: false);
        }
      } catch (e) {
        _setLastError(e);
        if (kDebugMode) {
          debugPrint(
            '[API] POST ' + url.toString() + ' error: ' + e.toString(),
          );
        }
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> fetchStatusRaw({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final j = await _getJson(['/api/status', '/state'], timeout: timeout);
    if (j == null || j['unauthorized'] == true) return null;
    final core = _extractStateCore(j);
    return core;
  }

  Future<Map<String, dynamic>?> fetchInfoRaw({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final j = await _getJson(['/info'], timeout: timeout);
    if (j == null || j['unauthorized'] == true) return null;
    return j;
  }

  Future<bool> testConnection() async {
    Future<bool> quickProbe(String path) async {
      try {
        final r = await http
            .get(_u(path), headers: authHeaders())
            .timeout(const Duration(milliseconds: 1200));
        return (r.statusCode >= 200 && r.statusCode < 300) ||
            r.statusCode == 401 ||
            r.statusCode == 403 ||
            r.statusCode == 429;
      } catch (_) {
        return false;
      }
    }

    if (await quickProbe('/api/status')) return true;
    if (await quickProbe('/state')) return true;
    if (_isSoftApBase()) {
      if (await quickProbe('/info')) return true;
      final apInfo = await _getJson([
        '/info',
      ], timeout: const Duration(milliseconds: 1800));
      if (apInfo != null) return true;
    }
    final j = await _getJson([
      '/api/status',
      '/state',
    ], timeout: const Duration(milliseconds: 2200));
    if (j != null) {
      if (j['unauthorized'] == true) {
        return true; // cihaz erişilebilir fakat kimlik doğrulaması gerekiyor
      }
      return true;
    }
    return false;
  }
}

class CloudApiService {
  CloudApiService(this.baseUrl);
  String baseUrl;
  String? bearerToken;
  Map<String, dynamic>? lastFetchedStateCore;
  String? lastClaimError;
  int? lastClaimHttpStatus;
  String? lastCmdError;
  String? lastCmdReason;
  int? lastCmdHttpStatus;
  String? lastCmdPath;

  Uri _u(String path) {
    final base = baseUrl.trim();
    if (base.isEmpty) return Uri.parse(path);
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.parse(normalized + path);
  }

  Future<Map<String, dynamic>?> _getJson(String path, Duration timeout) async {
    if (baseUrl.trim().isEmpty) return null;
    Uri? url;
    try {
      final headers = <String, String>{};
      final authOn = bearerToken != null && bearerToken!.isNotEmpty;
      if (authOn) {
        headers['Authorization'] = 'Bearer ${bearerToken!}';
      }
      url = _u(path);
      debugPrint('[CLOUD][HTTP] GET $url auth=${authOn ? 'on' : 'off'}');
      final r = await http.get(url, headers: headers).timeout(timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        if (r.body.isEmpty) return <String, dynamic>{};
        final obj = jsonDecode(r.body);
        if (obj is Map<String, dynamic>) return obj;
        return <String, dynamic>{'ok': true, 'body': obj};
      }
      final bodyPreview = r.body.length > 300
          ? r.body.substring(0, 300) + '...'
          : r.body;
      final target = url.toString();
      debugPrint(
        '[CLOUD][HTTP] GET $target -> ${r.statusCode} body=$bodyPreview',
      );
    } catch (e) {
      final target = url?.toString() ?? path;
      debugPrint('[CLOUD][HTTP] GET $target exception=$e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _postJson(
    String path,
    Map<String, dynamic> body,
    Duration timeout, {
    bool allowErrorBody = false,
  }) async {
    if (baseUrl.trim().isEmpty) return null;
    Uri? url;
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      final authOn = bearerToken != null && bearerToken!.isNotEmpty;
      if (authOn) {
        headers['Authorization'] = 'Bearer ${bearerToken!}';
      }
      url = _u(path);
      debugPrint('[CLOUD][HTTP] POST $url auth=${authOn ? 'on' : 'off'}');
      final r = await http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        if (path.contains('/invite') || path.contains('/join')) {
          final bodyPreview = r.body.length > 300
              ? r.body.substring(0, 300) + '...'
              : r.body;
          final target = url.toString();
          debugPrint(
            '[CLOUD][HTTP] POST $target -> ${r.statusCode} body=$bodyPreview',
          );
        }
        if (r.body.isEmpty) return <String, dynamic>{'ok': true};
        try {
          final obj = jsonDecode(r.body);
          if (obj is Map<String, dynamic>) return obj;
          return <String, dynamic>{'ok': true, 'body': obj};
        } catch (e) {
          final bodyPreview = r.body.length > 300
              ? r.body.substring(0, 300) + '...'
              : r.body;
          debugPrint(
            '[CLOUD][HTTP] POST $path -> ${r.statusCode} decode_error=$e body=$bodyPreview',
          );
          return null;
        }
      }
      final target = url.toString();
      final bodyPreview = r.body.length > 300
          ? r.body.substring(0, 300) + '...'
          : r.body;
      debugPrint(
        '[CLOUD][HTTP] POST $target -> ${r.statusCode} body=$bodyPreview',
      );
      if (allowErrorBody && r.body.isNotEmpty) {
        try {
          final obj = jsonDecode(r.body);
          if (obj is Map<String, dynamic>) {
            return <String, dynamic>{...obj, '_httpStatus': r.statusCode};
          }
          return <String, dynamic>{
            'ok': false,
            'body': obj,
            '_httpStatus': r.statusCode,
          };
        } catch (_) {
          return <String, dynamic>{
            'ok': false,
            'error': bodyPreview,
            '_httpStatus': r.statusCode,
          };
        }
      }
    } catch (e) {
      final target = url?.toString() ?? path;
      debugPrint('[CLOUD][HTTP] POST $target exception=$e');
    }
    return null;
  }

  bool _readBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  bool _isShadowDesiredFriendlyValue(dynamic v) {
    if (v == null) return true;
    return v is bool || v is num || v is String;
  }

  bool _shouldUseDesiredPathForCommand(Map<String, dynamic> body) {
    if (body.isEmpty) return false;
    final rawType = (body['type'] ?? body['cmd'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (rawType.isNotEmpty) return false;
    if (body.containsKey('desired')) return false;
    for (final entry in body.entries) {
      final key = entry.key;
      if (key == 'cmdId' || key == 'userIdHash' || key == 'acl') continue;
      if (!_isShadowDesiredFriendlyValue(entry.value)) return false;
    }
    return true;
  }

  String _previewMapKeys(Map<String, dynamic> m) {
    if (m.isEmpty) return '';
    final keys = m.keys.map((e) => e.toString()).toList();
    final preview = keys.take(6).join(',');
    return keys.length > 6 ? '$preview,…' : preview;
  }

  void _resetLastCmdDiag() {
    lastCmdError = null;
    lastCmdReason = null;
    lastCmdHttpStatus = null;
    lastCmdPath = null;
  }

  void clearLastCmdDiag() => _resetLastCmdDiag();

  void _setLastCmdDiag(String path, Map<String, dynamic>? j) {
    lastCmdPath = path;
    if (j == null) {
      lastCmdError ??= 'network_error';
      return;
    }
    if (j['_httpStatus'] is int) {
      lastCmdHttpStatus = j['_httpStatus'] as int;
    }
    final err = (j['err'] ?? j['error'] ?? j['code'] ?? '').toString().trim();
    final reason = (j['reason'] ?? j['message'] ?? '').toString().trim();
    if (err.isNotEmpty) lastCmdError = err;
    if (reason.isNotEmpty) lastCmdReason = reason;
  }

  Future<DeviceState?> fetchState(String id6, Duration timeout) async {
    final j = await _getJson('/device/$id6/state', timeout);
    if (j == null) return null;
    final auth = (j['auth'] is Map<String, dynamic>)
        ? (j['auth'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final role = auth['role'];
    final users = j['users'];
    final claim = (j['claim'] is Map<String, dynamic>)
        ? (j['claim'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final owner = (j['owner'] is Map<String, dynamic>)
        ? (j['owner'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final roleStr = role?.toString() ?? '';
    final usersNum = (users is List) ? users.length : 0;
    final ownerExists = _readBool(
      owner['hasOwner'] ??
          owner['ownerExists'] ??
          owner['exists'] ??
          owner['owner'],
    );
    final ownerKeys = _previewMapKeys(owner);
    if (role == null ||
        roleStr.isEmpty ||
        roleStr == 'UNKNOWN' ||
        usersNum == 0) {
      debugPrint(
        '[CLOUD][STATE][RAW] id6=$id6 role=$role users=$users usersNum=$usersNum '
        'claimed=${claim['claimed']} owner=$ownerExists ownerKeys=[$ownerKeys]',
      );
    }
    final core = _extractStateCore(j);
    lastFetchedStateCore = core;
    final ui = (core['ui'] is Map<String, dynamic>)
        ? (core['ui'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final rgb = (core['rgb'] is Map<String, dynamic>)
        ? (core['rgb'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final parsed = DeviceState.fromJson(core);
    debugPrint(
      '[CLOUD][RGB][RAW] id6=$id6 '
      'ui.rgbOn=${ui['rgbOn']} ui.rgbR=${ui['rgbR']} ui.rgbG=${ui['rgbG']} ui.rgbB=${ui['rgbB']} ui.rgbBrightness=${ui['rgbBrightness']} '
      'rgb.on=${rgb['on']} rgb.r=${rgb['r']} rgb.g=${rgb['g']} rgb.b=${rgb['b']} rgb.brightness=${rgb['brightness']}',
    );
    debugPrint(
      '[CLOUD][RGB][PARSED] id6=$id6 on=${parsed.rgbOn} '
      'rgb=(${parsed.r},${parsed.g},${parsed.b}) br=${parsed.rgbBrightness}',
    );
    return parsed;
  }

  Future<bool> sendCommand(
    String id6,
    Map<String, dynamic> body,
    Duration timeout, {
    bool tryDesired = true,
  }) async {
    _resetLastCmdDiag();
    final rawType = (body['type'] ?? body['cmd'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final isSpecialCmd =
        rawType == 'JOIN' ||
        body.containsKey('invite') ||
        body.containsKey('sig') ||
        body.containsKey('sig_owner') ||
        body.containsKey('sigOwner');

    if (!isSpecialCmd && tryDesired && _shouldUseDesiredPathForCommand(body)) {
      final desiredBody = body.containsKey('desired')
          ? Map<String, dynamic>.from(body)
          : <String, dynamic>{'desired': Map<String, dynamic>.from(body)};
      final desiredRes = await _postJson(
        '/device/$id6/desired',
        desiredBody,
        timeout,
        allowErrorBody: true,
      );
      if (desiredRes != null) {
        if (desiredRes['ok'] == true) return true;
        if (desiredRes.containsKey('state') || desiredRes.containsKey('fw'))
          return true;
        _setLastCmdDiag('/device/$id6/desired', desiredRes);
      }
    }

    final j = await _postJson(
      '/device/$id6/cmd',
      body,
      timeout,
      allowErrorBody: true,
    );
    if (j == null) {
      _setLastCmdDiag('/device/$id6/cmd', null);
      return false;
    }
    if (j['ok'] == true) return true;
    if (j.containsKey('state') || j.containsKey('fw')) return true;
    _setLastCmdDiag('/device/$id6/cmd', j);
    return false;
  }

  Future<bool> sendDesiredState(
    String id6,
    Map<String, dynamic> desired,
    Duration timeout, {
    bool allowFallbackCmd = true,
  }) async {
    _resetLastCmdDiag();
    final desiredBody = <String, dynamic>{
      'desired': Map<String, dynamic>.from(desired),
    };
    final j = await _postJson(
      '/device/$id6/desired',
      desiredBody,
      timeout,
      allowErrorBody: true,
    );
    if (j != null) {
      if (j['ok'] == true) return true;
      if (j.containsKey('state') || j.containsKey('fw')) return true;
      _setLastCmdDiag('/device/$id6/desired', j);
    } else {
      _setLastCmdDiag('/device/$id6/desired', null);
    }
    if (!allowFallbackCmd) return false;
    return sendCommand(id6, desiredBody, timeout, tryDesired: false);
  }

  Future<bool> testConnection(String id6, Duration timeout) async {
    final j = await _getJson('/device/$id6/state', timeout);
    return j != null;
  }

  Future<bool> claimDevice(
    String id6,
    Duration timeout, {
    String? claimSecret,
    String? userIdHash,
    String? ownerPubKeyB64,
    String? deviceBrand,
    String? deviceSuffix,
  }) async {
    lastClaimError = null;
    lastClaimHttpStatus = null;
    final secret = claimSecret?.trim();
    final secretHash = (secret != null && secret.isNotEmpty)
        ? sha256.convert(utf8.encode(secret)).toString()
        : null;
    final body = <String, dynamic>{
      if (secret != null && secret.isNotEmpty) 'claimSecret': secret,
      if (secret != null && secret.isNotEmpty) 'pairToken': secret,
      if (secretHash != null) 'claimSecretHash': secretHash,
      if (secretHash != null) 'pairTokenHash': secretHash,
      if (secretHash != null)
        'claimProof': <String, dynamic>{
          'hash': secretHash,
          'claimSecretHash': secretHash,
          'pairTokenHash': secretHash,
          'algo': 'sha256',
          'v': 2,
        },
      if (userIdHash != null && userIdHash.isNotEmpty) 'userIdHash': userIdHash,
      if (ownerPubKeyB64 != null && ownerPubKeyB64.isNotEmpty)
        'ownerPubKey': ownerPubKeyB64,
      if (deviceBrand != null && deviceBrand.trim().isNotEmpty)
        'deviceBrand': deviceBrand.trim(),
      if (deviceSuffix != null) 'deviceSuffix': deviceSuffix.trim(),
    };
    final j = await _postJson(
      '/device/$id6/claim',
      body,
      timeout,
      allowErrorBody: true,
    );
    if (j == null) {
      lastClaimError = 'network_error';
      return false;
    }
    if (j['_httpStatus'] is int) {
      lastClaimHttpStatus = j['_httpStatus'] as int;
    }
    if (j['ok'] == true) return true;
    if (j['linked'] == true) return true;
    final role = (j['role'] ?? '').toString().toUpperCase();
    if (role == 'OWNER') return true;
    if (j['owner'] == true || j['claimed'] == true) return true;
    lastClaimError = (j['err'] ?? j['error'] ?? '').toString().trim();
    if (lastClaimError == null || lastClaimError!.isEmpty) {
      lastClaimError = 'claim_failed';
    }
    return false;
  }

  Future<bool> syncClaimProof(
    String id6,
    Duration timeout, {
    String? claimSecret,
    String? userIdHash,
    String? ownerPubKeyB64,
  }) async {
    final secret = claimSecret?.trim();
    if (secret == null || secret.isEmpty) {
      lastClaimError = 'claim_proof_required';
      return false;
    }
    final secretHash = sha256.convert(utf8.encode(secret)).toString();
    final body = <String, dynamic>{
      'claimSecret': secret,
      'pairToken': secret,
      'claimSecretHash': secretHash,
      'pairTokenHash': secretHash,
      'claimProof': <String, dynamic>{
        'hash': secretHash,
        'claimSecretHash': secretHash,
        'pairTokenHash': secretHash,
        'algo': 'sha256',
        'v': 2,
      },
      if (userIdHash != null && userIdHash.isNotEmpty) 'userIdHash': userIdHash,
      if (ownerPubKeyB64 != null && ownerPubKeyB64.isNotEmpty)
        'ownerPubKey': ownerPubKeyB64,
    };
    final j = await _postJson(
      '/device/$id6/claim-proof/sync',
      body,
      timeout,
      allowErrorBody: true,
    );
    if (j == null) {
      lastClaimError = 'network_error';
      return false;
    }
    if (j['_httpStatus'] is int) {
      lastClaimHttpStatus = j['_httpStatus'] as int;
    }
    if (j['ok'] == true || j['claimProofSynced'] == true) return true;
    lastClaimError = (j['err'] ?? j['error'] ?? 'claim_proof_sync_failed')
        .toString()
        .trim();
    if (lastClaimError == null || lastClaimError!.isEmpty) {
      lastClaimError = 'claim_proof_sync_failed';
    }
    return false;
  }

  Future<bool> claimDeviceWithAutoSync(
    String id6,
    Duration timeout, {
    String? claimSecret,
    String? userIdHash,
    String? ownerPubKeyB64,
    String? deviceBrand,
    String? deviceSuffix,
  }) async {
    final ok = await claimDevice(
      id6,
      timeout,
      claimSecret: claimSecret,
      userIdHash: userIdHash,
      ownerPubKeyB64: ownerPubKeyB64,
      deviceBrand: deviceBrand,
      deviceSuffix: deviceSuffix,
    );
    if (ok) return true;
    final claimErr = (lastClaimError ?? '').trim();
    final shouldSyncProof =
        claimErr == 'claim_proof_not_initialized' ||
        claimErr == 'claim_proof_required' ||
        claimErr == 'claim_proof_mismatch';
    if (!shouldSyncProof) return false;
    final synced = await syncClaimProof(
      id6,
      timeout,
      claimSecret: claimSecret,
      userIdHash: userIdHash,
      ownerPubKeyB64: ownerPubKeyB64,
    );
    if (!synced) {
      // UI'da teknik bootstrap detayı göstermeyelim.
      if ((lastClaimError ?? '') == 'claim_proof_not_initialized' ||
          (lastClaimError ?? '') == 'claim_proof_sync_failed') {
        lastClaimError = 'claim_failed';
      }
      return false;
    }
    final claimed = await claimDevice(
      id6,
      timeout,
      claimSecret: claimSecret,
      userIdHash: userIdHash,
      ownerPubKeyB64: ownerPubKeyB64,
      deviceBrand: deviceBrand,
      deviceSuffix: deviceSuffix,
    );
    if (!claimed) {
      final claimErr = (lastClaimError ?? '').trim();
      final shouldRecover =
          claimErr == 'claim_proof_required' ||
          claimErr == 'claim_proof_mismatch' ||
          claimErr == 'already_claimed';
      if (shouldRecover &&
          claimSecret != null &&
          claimSecret.trim().isNotEmpty) {
        final recovered = await recoverOwnership(
          id6,
          timeout,
          claimSecret: claimSecret,
          userIdHash: userIdHash,
          ownerPubKeyB64: ownerPubKeyB64,
          deviceBrand: deviceBrand,
          deviceSuffix: deviceSuffix,
        );
        if (recovered) return true;
      }
      if ((lastClaimError ?? '') == 'claim_proof_not_initialized') {
        lastClaimError = 'claim_failed';
      }
    }
    return claimed;
  }

  Future<bool> unclaimDevice(String id6, Duration timeout) async {
    Map<String, dynamic>? j = await _postJson(
      '/device/$id6/unclaim',
      <String, dynamic>{},
      timeout,
    );
    if (j == null || j['ok'] != true) {
      j = await _postJson('/device/unclaim', <String, dynamic>{
        'id6': id6,
      }, timeout);
    }
    if (j == null) return false;
    if (j['ok'] == true) return true;
    return false;
  }

  Future<bool> recoverOwnership(
    String id6,
    Duration timeout, {
    String? claimSecret,
    String? userIdHash,
    String? ownerPubKeyB64,
    String? deviceBrand,
    String? deviceSuffix,
  }) async {
    lastClaimError = null;
    lastClaimHttpStatus = null;
    final secret = claimSecret?.trim();
    if (secret == null || secret.isEmpty) {
      lastClaimError = 'claim_proof_required';
      return false;
    }
    final secretHash = sha256.convert(utf8.encode(secret)).toString();
    final j = await _postJson(
      '/device/$id6/claim/recover',
      <String, dynamic>{
        'confirmRecovery': true,
        'claimSecret': secret,
        'pairToken': secret,
        'claimSecretHash': secretHash,
        'pairTokenHash': secretHash,
        'claimProof': <String, dynamic>{
          'hash': secretHash,
          'claimSecretHash': secretHash,
          'pairTokenHash': secretHash,
          'algo': 'sha256',
          'v': 2,
        },
        if (userIdHash != null && userIdHash.isNotEmpty)
          'userIdHash': userIdHash,
        if (ownerPubKeyB64 != null && ownerPubKeyB64.isNotEmpty)
          'ownerPubKey': ownerPubKeyB64,
        if (deviceBrand != null && deviceBrand.trim().isNotEmpty)
          'deviceBrand': deviceBrand.trim(),
        if (deviceSuffix != null) 'deviceSuffix': deviceSuffix.trim(),
      },
      timeout,
      allowErrorBody: true,
    );
    if (j == null) {
      lastClaimError = 'network_error';
      return false;
    }
    if (j['_httpStatus'] is int) {
      lastClaimHttpStatus = j['_httpStatus'] as int;
    }
    if (j['ok'] == true || j['recovered'] == true || j['linked'] == true) {
      return true;
    }
    lastClaimError = (j['err'] ?? j['error'] ?? 'ownership_recovery_failed')
        .toString()
        .trim();
    if (lastClaimError == null || lastClaimError!.isEmpty) {
      lastClaimError = 'ownership_recovery_failed';
    }
    return false;
  }

  Future<Map<String, dynamic>?> createInvite(
    String id6, {
    String role = 'USER',
    int ttl = 600,
    String? userIdHash,
    String? inviteeEmail,
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final idHash = userIdHash;
    final j = await _postJson('/device/$id6/invite', <String, dynamic>{
      'role': role,
      'ttl': ttl,
      if (idHash != null && idHash.isNotEmpty) 'userIdHash': idHash,
      if (inviteeEmail != null && inviteeEmail.trim().isNotEmpty)
        'inviteeEmail': inviteeEmail.trim(),
    }, timeout);
    if (j == null) {
      debugPrint('[CLOUD][INVITE] null response');
      return null;
    }
    final keys = j.keys.map((e) => e.toString()).take(10).join(',');
    debugPrint(
      '[CLOUD][INVITE] raw keys=[$keys] ok=${j['ok']} err=${j['err']}',
    );
    if (j['invite'] is Map<String, dynamic>) {
      return (j['invite'] as Map<String, dynamic>);
    }
    if (j['invite'] is Map) {
      return Map<String, dynamic>.from(j['invite'] as Map);
    }
    if (j.containsKey('inviteId') || j.containsKey('invite_id')) {
      return Map<String, dynamic>.from(j);
    }
    debugPrint(
      '[CLOUD][INVITE] unexpected response keys=[$keys] ok=${j['ok']} err=${j['err']}',
    );
    return null;
  }

  Future<Map<String, dynamic>?> fetchStateJson(
    String id6,
    Duration timeout,
  ) async {
    return _getJson('/device/$id6/state', timeout);
  }

  Future<Map<String, dynamic>?> fetchMe(Duration timeout) async {
    final j = await _getJson('/me', timeout);
    if (j == null) return null;
    if (j['ok'] == true && j['me'] is Map) {
      final me = Map<String, dynamic>.from(j['me'] as Map);
      if (j['cloud'] is Map) {
        me['_cloud'] = Map<String, dynamic>.from(j['cloud'] as Map);
      }
      return me;
    }
    if (j['sub'] != null || j['email'] != null) {
      return Map<String, dynamic>.from(j);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> listDevices(Duration timeout) async {
    final j = await _getJson('/devices', timeout);
    if (j == null) return null;
    final raw = j['devices'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  Future<Map<String, dynamic>?> updateDeviceName(
    String id6, {
    required String brand,
    String suffix = '',
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final normalizedId6 = normalizeDeviceId6(id6);
    if (normalizedId6 == null || normalizedId6.isEmpty) {
      debugPrint('[CLOUD][HTTP] skip updateDeviceName invalid id6=$id6');
      return null;
    }
    final j = await _postJson(
      '/device/$normalizedId6/name',
      <String, dynamic>{
        'deviceBrand': brand.trim(),
        'deviceSuffix': suffix.trim(),
      },
      timeout,
      allowErrorBody: true,
    );
    if (j == null) return null;
    if (j['ok'] == true) return j;
    return null;
  }

  Future<Map<String, dynamic>?> fetchCapabilities(
    String id6,
    Duration timeout,
  ) async {
    final j = await _getJson('/device/$id6/capabilities', timeout);
    if (j == null) return null;
    if (j['ok'] == true && j['capabilities'] is Map) {
      return Map<String, dynamic>.from(j);
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchHaConfig(
    String id6,
    Duration timeout,
  ) async {
    final j = await _getJson('/device/$id6/ha/config', timeout);
    if (j == null) return null;
    if (j['ok'] == true && j['messages'] is List) {
      return Map<String, dynamic>.from(j);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> listInvites(
    String id6,
    Duration timeout,
  ) async {
    final j = await _getJson('/device/$id6/invites', timeout);
    if (j == null) return null;
    final raw = j['invites'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  Future<List<Map<String, dynamic>>?> listMyInvites(Duration timeout) async {
    final j = await _getJson('/me/invites', timeout);
    if (j == null) return null;
    final raw = j['invites'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  Future<Map<String, dynamic>?> revokeInvite(
    String id6,
    String inviteId, {
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final encoded = Uri.encodeComponent(inviteId.trim());
    final j = await _postJson(
      '/device/$id6/invite/$encoded/revoke',
      <String, dynamic>{'inviteId': inviteId},
      timeout,
    );
    if (j == null) return null;
    if (j['ok'] == true || j['revoked'] == true) return j;
    return null;
  }

  Future<List<Map<String, dynamic>>?> listMembers(
    String id6,
    Duration timeout,
  ) async {
    final j = await _getJson('/device/$id6/members', timeout);
    if (j == null) return null;
    final raw = j['members'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  Future<Map<String, dynamic>?> revokeMember(
    String id6,
    String userSub, {
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final encoded = Uri.encodeComponent(userSub.trim());
    final j = await _postJson(
      '/device/$id6/member/$encoded/revoke',
      <String, dynamic>{'userSub': userSub},
      timeout,
    );
    if (j == null) return null;
    if (j['ok'] == true || j['revoked'] == true) return j;
    return null;
  }

  Future<Map<String, dynamic>?> pushAcl(
    String id6, {
    Duration timeout = kCloudConnectTimeout,
  }) async {
    // Owner-only, best-effort shadow desired ACL sync.
    final j = await _postJson(
      '/device/$id6/acl/push',
      <String, dynamic>{},
      timeout,
      allowErrorBody: true,
    );
    if (j == null) return null;
    // Return body even on error so caller can show `reason`/`err`.
    return j;
  }

  Future<Map<String, dynamic>?> createIntegrationLink(
    String id6, {
    required String integrationId,
    List<String> scopes = const <String>['device:read'],
    int ttlSec = 30 * 24 * 3600,
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final normalizedScopes = scopes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final j = await _postJson(
      '/device/$id6/integration/link',
      <String, dynamic>{
        'integrationId': integrationId.trim(),
        'scopes': normalizedScopes,
        'ttlSec': ttlSec,
      },
      timeout,
      allowErrorBody: true,
    );
    if (j == null) return null;
    if (j['ok'] == true || j['linked'] == true) return j;
    return null;
  }

  Future<List<Map<String, dynamic>>?> listIntegrations(
    String id6,
    Duration timeout,
  ) async {
    final j = await _getJson('/device/$id6/integrations', timeout);
    if (j == null) return null;
    final raw = j['integrations'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  Future<Map<String, dynamic>?> revokeIntegrationLink(
    String id6,
    String integrationId, {
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final encoded = Uri.encodeComponent(integrationId.trim());
    final j = await _postJson(
      '/device/$id6/integration/$encoded/revoke',
      <String, dynamic>{'integrationId': integrationId},
      timeout,
      allowErrorBody: true,
    );
    if (j == null) return null;
    if (j['ok'] == true || j['revoked'] == true) return j;
    return null;
  }

  Future<Map<String, dynamic>?> joinInvite(
    String id6,
    String inviteId, {
    Map<String, dynamic>? invitePayload,
    String? userIdHash,
    Duration timeout = kCloudConnectTimeout,
  }) async {
    // Signed cloud invites require an inviteToken (returned by /device/{id6}/invite).
    // Accept both top-level and nested (invite/inviteQr) layouts for QR payloads.
    String? inviteToken;
    if (invitePayload != null) {
      final raw =
          invitePayload['inviteToken'] ??
          invitePayload['invite_token'] ??
          invitePayload['token'];
      if (raw != null) inviteToken = raw.toString();
      final nestedInvite = invitePayload['invite'];
      if ((inviteToken == null || inviteToken.isEmpty) && nestedInvite is Map) {
        final raw2 =
            nestedInvite['inviteToken'] ??
            nestedInvite['invite_token'] ??
            nestedInvite['token'];
        if (raw2 != null) inviteToken = raw2.toString();
      }
      final nestedQr = invitePayload['inviteQr'];
      if ((inviteToken == null || inviteToken.isEmpty) && nestedQr is Map) {
        final raw3 =
            nestedQr['inviteToken'] ??
            nestedQr['invite_token'] ??
            nestedQr['token'];
        if (raw3 != null) inviteToken = raw3.toString();
      }
    }
    final j = await _postJson('/device/$id6/claim', <String, dynamic>{
      'inviteId': inviteId,
      if (inviteToken != null && inviteToken.trim().isNotEmpty)
        'inviteToken': inviteToken.trim(),
      if (userIdHash != null && userIdHash.isNotEmpty) 'userIdHash': userIdHash,
      if (invitePayload != null) 'invite': invitePayload,
    }, timeout);
    if (j == null) return null;
    if (j['ok'] == true) return j;
    return null;
  }

  Future<Map<String, dynamic>?> createOtaJob(
    String id6, {
    required String firmwareUrl,
    required String sha256,
    required String version,
    String? minVersion,
    String? product,
    String? hwRev,
    String? boardRev,
    String? fwChannel,
    bool force = false,
    bool dryRun = false,
    Duration timeout = kCloudConnectTimeout,
  }) async {
    final target = <String, dynamic>{};
    if (product != null && product.trim().isNotEmpty) {
      target['product'] = product.trim().toLowerCase();
    }
    if (hwRev != null && hwRev.trim().isNotEmpty) {
      target['hwRev'] = hwRev.trim().toLowerCase();
    }
    if (boardRev != null && boardRev.trim().isNotEmpty) {
      target['boardRev'] = boardRev.trim().toLowerCase();
    }
    if (fwChannel != null && fwChannel.trim().isNotEmpty) {
      target['fwChannel'] = fwChannel.trim().toLowerCase();
    }
    final body = <String, dynamic>{
      'firmwareUrl': firmwareUrl.trim(),
      'sha256': sha256.trim(),
      'version': version.trim(),
      'force': force,
      'dryRun': dryRun,
      if (minVersion != null && minVersion.trim().isNotEmpty)
        'minVersion': minVersion.trim(),
      if (target.isNotEmpty) 'target': target,
    };
    final j = await _postJson('/device/$id6/ota/job', body, timeout);
    if (j == null) return null;
    if (j['ok'] == true || j['jobCreated'] == true) return j;
    return null;
  }
}

// Cloud auth (Cognito Hosted UI)
const String kCognitoRegion = String.fromEnvironment(
  'COGNITO_REGION',
  defaultValue: 'eu-central-1',
);
const String kCognitoUserPoolId = String.fromEnvironment(
  'COGNITO_USER_POOL_ID',
  defaultValue: 'eu-central-1_KuBlWrAt7',
);
const String kCognitoClientId = String.fromEnvironment(
  'COGNITO_CLIENT_ID',
  defaultValue: '3edajq3f7eu6sbrva8qsrnd0ep',
);
const String kCognitoIssuer =
    'https://cognito-idp.$kCognitoRegion.amazonaws.com/$kCognitoUserPoolId';
const String kCognitoHostedDomain = String.fromEnvironment(
  'COGNITO_HOSTED_DOMAIN',
  defaultValue:
      'https://aac-dev-824155916831.auth.eu-central-1.amazoncognito.com',
);
const String kCognitoRedirectUriIos = String.fromEnvironment(
  'COGNITO_REDIRECT_URI_IOS',
  defaultValue: 'com.koray.artaircleaner://callback',
);
const String kCognitoRedirectUriAndroid = String.fromEnvironment(
  'COGNITO_REDIRECT_URI_ANDROID',
  defaultValue: 'com.koray.artaircleaner://callback',
);
const String kCognitoRedirectUriAndroidLegacy = String.fromEnvironment(
  'COGNITO_REDIRECT_URI_ANDROID_LEGACY',
  defaultValue: '',
);
const String kDefaultCloudApiBase =
    'https://3wl1he0yj3.execute-api.eu-central-1.amazonaws.com';

// ===== Home =====
