import 'package:secure_id/services/account_session.dart';

/// Deterministic account backend for sync tests.
class FakeAccountSession implements AccountSession {
  FakeAccountSession({
    this.userId = 'user-1',
    this.signUpOutcome = SignUpOutcome.signedIn,
  });

  final String userId;
  final SignUpOutcome signUpOutcome;

  AccountUser? _user;
  String? lastEmail;
  bool failNext = false;
  String failureMessage = 'The account service rejected the request.';

  @override
  bool get isAvailable => true;

  @override
  AccountUser? get currentUser => _user;

  @override
  Stream<AccountUser?> get userChanges => const Stream<AccountUser?>.empty();

  void setSignedIn(AccountUser? user) => _user = user;

  @override
  Future<AccountUser> signIn({
    required String email,
    required String password,
  }) async {
    if (failNext) throw AccountException(failureMessage);
    lastEmail = email;
    _user = AccountUser(id: userId, email: email);
    return _user!;
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    if (failNext) throw AccountException(failureMessage);
    lastEmail = email;
    _user = AccountUser(id: userId, email: email);
    return signUpOutcome;
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }
}
