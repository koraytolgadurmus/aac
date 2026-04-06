part of 'main.dart';

// Time-series point used by charts/history widgets.
class _HistoryPoint {
  final DateTime time;
  final double value;
  const _HistoryPoint(this.time, this.value);
}

// Reassembles JSON frames split across BLE notification chunks.
class _BleJsonFramer {
  String _buf = '';
  bool _started = false;
  int _depth = 0;
  bool _inString = false;
  bool _esc = false;

  static const int _maxBuf = 32768;
  static const List<String> _rootKeys = <String>[
    'fwVersion',
    'auth',
    'aps',
    'network',
    'wifi',
    'prov',
    'status',
    'owner',
    'claim',
    'invite',
    'apSession',
    'ok',
  ];

  void reset() {
    _buf = '';
    _started = false;
    _depth = 0;
    _inString = false;
    _esc = false;
  }

  int get bufferedLength => _buf.length;

  bool _looksLikeRootStart(String s, int i) {
    if (i < 0 || i >= s.length) return false;
    if (s.codeUnitAt(i) != 0x7B) return false; // {
    if (i + 2 >= s.length) return false;
    if (s.codeUnitAt(i + 1) != 0x22) return false; // "
    for (final k in _rootKeys) {
      final pat = '{"$k"';
      if (s.startsWith(pat, i)) return true;
    }
    return false;
  }

  List<String> feed(String chunk) {
    final out = <String>[];
    if (chunk.isEmpty) return out;

    for (int i = 0; i < chunk.length; i++) {
      final ch = chunk[i];

      if (!_started) {
        if (ch != '{') continue;
        if (!_looksLikeRootStart(chunk, i)) continue;
        reset();
        _started = true;
        _depth = 1;
        _buf = '{';
        continue;
      }

      if (!_inString &&
          !_esc &&
          ch == '{' &&
          i == 0 &&
          _looksLikeRootStart(chunk, i)) {
        reset();
        _started = true;
        _depth = 1;
        _buf = '{';
        continue;
      }

      _buf += ch;
      if (_buf.length > _maxBuf) {
        reset();
        continue;
      }

      if (_esc) {
        _esc = false;
        continue;
      }
      if (_inString) {
        if (ch == '\\') {
          _esc = true;
        } else if (ch == '"') {
          _inString = false;
        }
        continue;
      }

      if (ch == '"') {
        _inString = true;
        continue;
      }
      if (ch == '{') {
        _depth++;
      } else if (ch == '}') {
        _depth--;
        if (_depth == 0) {
          out.add(_buf);
          reset();
        }
      }
    }
    return out;
  }
}

class _DeviceRuntimeContext {
  String? apSessionToken;
  String? apSessionNonce;
  DateTime? lastLocalOkAt;
  DateTime? localDnsFailUntil;
  DateTime? localUnreachableUntil;
  DateTime? lastCloudOkAt;
  DateTime? cloudFailUntil;
  DateTime? cloudPreferUntil;
  bool? cloudOwnerExistsOverride;
  bool? cloudOwnerSetupDoneOverride;
  DateTime? lastSeenAt;
  bool lastConnected = false;
}
