part of 'main.dart';

class InvitedUser {
  final String id;
  final String role;
  final String? pubkey;
  InvitedUser({required this.id, required this.role, this.pubkey});

  factory InvitedUser.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? j['userIdHash'] ?? '').toString();
    final role = (j['role'] ?? 'USER').toString();
    final pub = (j['pubkey'] ?? j['pubKey'] ?? '').toString();
    return InvitedUser(
      id: id,
      role: role.isEmpty ? 'USER' : role,
      pubkey: pub.isEmpty ? null : pub,
    );
  }
}
