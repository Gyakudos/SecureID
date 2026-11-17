import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/models/totp.dart';
import 'package:secure_id/models/vault_item.dart';
import 'package:secure_id/security/vault_audit.dart';

void main() {
  const strong = 'vN7#qL2!tR9@wX4\$';
  final totp = TotpData(secret: 'JBSWY3DPEHPK3PXP');

  VaultItem login(String id, String title, String password, {TotpData? totp}) =>
      VaultItem(
        id: id,
        kind: VaultItemKind.login,
        title: title,
        username: '$id@example.com',
        password: password,
        totp: totp,
      );

  List<VaultAuditIssue> issuesOf(VaultAuditReport report) => [
    for (final finding in report.findings) finding.issue,
  ];

  test('an empty password is the only finding for that login', () {
    final report = auditVault([login('a', 'Alpha', '')]);

    expect(report.logins, 1);
    expect(report.findings, hasLength(1));
    expect(report.findings.single.issue, VaultAuditIssue.emptyPassword);
    expect(report.countOf(VaultAuditIssue.emptyPassword), 1);
    // 100 - 25 for the missing password.
    expect(report.score, 75);
    expect(report.isClean, isFalse);
  });

  test('a weak password is flagged with its strength label', () {
    final report = auditVault([login('a', 'Alpha', '123456', totp: totp)]);

    expect(issuesOf(report), [VaultAuditIssue.weakPassword]);
    expect(report.findings.single.detail, contains('Very weak'));
    // 100 - 15 for the weak password.
    expect(report.score, 85);
  });

  test('a strong unique password with 2FA has no findings', () {
    final report = auditVault([login('a', 'Alpha', strong, totp: totp)]);

    expect(report.logins, 1);
    expect(report.isClean, isTrue);
    expect(report.score, 100);
    expect(report.scoreLabel, 'Excellent');
  });

  test('a strong password without 2FA is only a warning', () {
    final report = auditVault([login('a', 'Alpha', strong)]);

    expect(issuesOf(report), [VaultAuditIssue.missingTwoFactor]);
    // 100 - 5 for the missing second factor.
    expect(report.score, 95);
  });

  test('a shared password is flagged on every login that uses it', () {
    final report = auditVault([
      login('a', 'Alpha', strong, totp: totp),
      login('b', 'Bravo', strong, totp: totp),
    ]);

    expect(issuesOf(report), [
      VaultAuditIssue.reusedPassword,
      VaultAuditIssue.reusedPassword,
    ]);
    expect(report.findings.first.detail, contains('1 other login'));
    expect(report.countOf(VaultAuditIssue.reusedPassword), 2);
    // 100 - 10 for each of the two reused passwords.
    expect(report.score, 80);
  });

  test('empty passwords are never reported as reused', () {
    final report = auditVault([
      login('a', 'Alpha', ''),
      login('b', 'Bravo', ''),
    ]);

    expect(issuesOf(report), [
      VaultAuditIssue.emptyPassword,
      VaultAuditIssue.emptyPassword,
    ]);
    expect(report.countOf(VaultAuditIssue.reusedPassword), 0);
  });

  test('passkeys and authenticator entries are not audited', () {
    final report = auditVault([
      login('login', 'Login', strong, totp: totp),
      VaultItem(
        id: 'passkey',
        kind: VaultItemKind.passkey,
        title: 'Passkey',
        password: '123456',
      ),
      VaultItem(
        id: 'totp',
        kind: VaultItemKind.totp,
        title: 'Authenticator',
        password: '123456',
        totp: totp,
      ),
    ]);

    expect(report.logins, 1);
    expect(report.isClean, isTrue);
    expect(report.score, 100);
  });

  test('an empty vault scores 100 and has nothing to check', () {
    final report = auditVault(const []);

    expect(report.logins, 0);
    expect(report.isClean, isTrue);
    expect(report.score, 100);
    expect(report.scoreLabel, 'Nothing to check yet');
  });

  test('findings are grouped by issue and then sorted by title', () {
    final report = auditVault([
      login('b', 'Bravo', '123456'),
      login('a', 'Alpha', ''),
      login('c', 'Charlie', strong),
    ]);

    expect(issuesOf(report), [
      VaultAuditIssue.emptyPassword,
      VaultAuditIssue.weakPassword,
      VaultAuditIssue.missingTwoFactor,
      VaultAuditIssue.missingTwoFactor,
    ]);
    expect(
      [for (final finding in report.findings) finding.item.title],
      ['Alpha', 'Bravo', 'Bravo', 'Charlie'],
    );
    expect(report.findingsFor(VaultAuditIssue.missingTwoFactor), hasLength(2));
    expect(report.countOf(VaultAuditIssue.emptyPassword), 1);
    expect(report.countOf(VaultAuditIssue.weakPassword), 1);
    expect(report.countOf(VaultAuditIssue.missingTwoFactor), 2);
    // 25 + 15 + 5 + 5.
    expect(report.score, 50);
    expect(report.scoreLabel, 'Needs attention');
  });

  test('the score never drops below zero', () {
    final report = auditVault([
      for (var index = 0; index < 6; index++)
        login('$index', 'Login $index', '123456'),
    ]);

    expect(report.findings.length, 18);
    expect(report.score, 0);
    expect(report.scoreLabel, 'At risk');
  });
}
