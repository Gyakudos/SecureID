import 'package:supabase_flutter/supabase_flutter.dart';

/// A signed-in SecureID account.
///
/// The account is only used for authentication and for addressing the synced
/// vault row. The master password is never sent to the server.
class AccountUser {
  const AccountUser({required this.id, this.email});

  final String id;
  final String? email;

  String get displayName => (email == null || email!.isEmpty) ? id : email!;

  @override
  bool operator ==(Object other) =>
      other is AccountUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

/// What happened after asking the backend to create an account.
enum SignUpOutcome {
  /// The account was created and a session is active.
  signedIn,

  /// The account was created but the user must confirm their email first.
  confirmationRequired,
}

/// A user-facing account failure.
class AccountException implements Exception {
  const AccountException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Authentication boundary. Implemented by Supabase in production and by a
/// fake in tests.
abstract class AccountSession {
  bool get isAvailable;

  AccountUser? get currentUser;

  /// Emits when the SDK restores, refreshes or clears the session.
  Stream<AccountUser?> get userChanges;

  Future<AccountUser> signIn({required String email, required String password});

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// Supabase email/password authentication.
class SupabaseAccountSession implements AccountSession {
  SupabaseAccountSession(this._client);

  final SupabaseClient _client;

  @override
  bool get isAvailable => true;

  @override
  AccountUser? get currentUser => _mapUser(_client.auth.currentUser);

  @override
  Stream<AccountUser?> get userChanges => _client.auth.onAuthStateChange
      .map((state) => _mapUser(state.session?.user))
      .distinct();

  @override
  Future<AccountUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = _mapUser(response.user);
      if (user == null) {
        throw const AccountException(
          'The account service did not return a user.',
        );
      }
      return user;
    } on AuthException catch (error) {
      throw AccountException(_friendlyMessage(error));
    } on AccountException {
      rethrow;
    } catch (_) {
      throw const AccountException(
        'Could not reach the account service. Check your connection and try again.',
      );
    }
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (response.session == null) {
        return SignUpOutcome.confirmationRequired;
      }
      return SignUpOutcome.signedIn;
    } on AuthException catch (error) {
      throw AccountException(_friendlyMessage(error));
    } catch (_) {
      throw const AccountException(
        'Could not reach the account service. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException {
      // The local session is cleared by the SDK even if the server call fails.
    } catch (_) {
      // Signing out locally is always safe; the vault stays on disk.
    }
  }

  static AccountUser? _mapUser(User? user) {
    if (user == null) return null;
    return AccountUser(id: user.id, email: user.email);
  }

  static String _friendlyMessage(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email address before signing in. Check your inbox.';
    }
    if (message.contains('user already registered')) {
      return 'An account with that email already exists. Sign in instead.';
    }
    if (message.contains('password should be at least')) {
      return 'Use a password with at least 6 characters.';
    }
    if (message.contains('invalid email') ||
        message.contains('unable to validate email')) {
      return 'Enter a valid email address.';
    }
    if (message.contains('rate limit') || error.statusCode == '429') {
      return 'Too many attempts. Wait a moment and try again.';
    }
    return error.message;
  }
}
