import '../models/vault_item.dart';
import 'password_strength.dart';

/// A problem the offline vault audit can find in a login.
enum VaultAuditIssue {
  emptyPassword,
  weakPassword,
  reusedPassword,
  missingTwoFactor,
}

extension VaultAuditIssueInfo on VaultAuditIssue {
  /// Heading shown for a group of findings.
  String get label => switch (this) {
    VaultAuditIssue.emptyPassword => 'No password',
    VaultAuditIssue.weakPassword => 'Weak passwords',
    VaultAuditIssue.reusedPassword => 'Reused passwords',
    VaultAuditIssue.missingTwoFactor => 'No two-factor code',
  };

  /// One-line explanation of why the issue matters.
  String get summary => switch (this) {
    VaultAuditIssue.emptyPassword => 'These logins have no password saved yet.',
    VaultAuditIssue.weakPassword =>
      'Short or predictable passwords are the first ones guessed.',
    VaultAuditIssue.reusedPassword =>
      'One leaked password would unlock every account that shares it.',
    VaultAuditIssue.missingTwoFactor =>
      'A second factor keeps an account safe even if the password leaks.',
  };

  /// How much this issue lowers the score. Missing 2FA is a warning, not a
  /// broken password, so it weighs less.
  int get weight => switch (this) {
    VaultAuditIssue.emptyPassword => 25,
    VaultAuditIssue.weakPassword => 15,
    VaultAuditIssue.reusedPassword => 10,
    VaultAuditIssue.missingTwoFactor => 5,
  };
}

/// One login and the reason it was flagged.
class VaultAuditFinding {
  const VaultAuditFinding({
    required this.item,
    required this.issue,
    required this.detail,
  });

  final VaultItem item;
  final VaultAuditIssue issue;

  /// A short, item-specific explanation.
  final String detail;
}

/// The result of auditing every login in the vault.
class VaultAuditReport {
  const VaultAuditReport({
    required this.findings,
    required this.logins,
    required this.score,
    required this.counts,
  });

  /// All findings, grouped by issue and then sorted by title.
  final List<VaultAuditFinding> findings;

  /// How many login items were checked.
  final int logins;

  /// 0 (at risk) to 100 (nothing found).
  final int score;

  final Map<VaultAuditIssue, int> counts;

  bool get isClean => findings.isEmpty;

  int countOf(VaultAuditIssue issue) => counts[issue] ?? 0;

  List<VaultAuditFinding> findingsFor(VaultAuditIssue issue) => [
    for (final finding in findings)
      if (finding.issue == issue) finding,
  ];

  String get scoreLabel {
    if (logins == 0) return 'Nothing to check yet';
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 50) return 'Needs attention';
    return 'At risk';
  }
}

/// Audits [items] without any network access.
///
/// Only logins are checked. Passkeys and standalone authenticator entries have
/// no password to score. The report is deterministic, so the same vault always
/// produces the same findings and score.
VaultAuditReport auditVault(List<VaultItem> items) {
  final logins = [
    for (final item in items)
      if (item.isLogin) item,
  ];

  final byPassword = <String, List<VaultItem>>{};
  for (final item in logins) {
    if (item.password.isEmpty) continue;
    byPassword.putIfAbsent(item.password, () => []).add(item);
  }

  final findings = <VaultAuditFinding>[];
  for (final item in logins) {
    if (item.password.isEmpty) {
      findings.add(
        VaultAuditFinding(
          item: item,
          issue: VaultAuditIssue.emptyPassword,
          detail: 'No password saved yet.',
        ),
      );
      // An empty password cannot also be weak or reused.
      continue;
    }

    final strength = estimatePasswordStrength(item.password);
    if (strength.score <= 1) {
      findings.add(
        VaultAuditFinding(
          item: item,
          issue: VaultAuditIssue.weakPassword,
          detail: '${strength.label} · about ${strength.bits.round()} bits',
        ),
      );
    }

    final shared = byPassword[item.password];
    if (shared != null && shared.length > 1) {
      final others = shared.length - 1;
      findings.add(
        VaultAuditFinding(
          item: item,
          issue: VaultAuditIssue.reusedPassword,
          detail:
              'Shared with $others other ${others == 1 ? 'login' : 'logins'}.',
        ),
      );
    }

    if (!item.hasTotp) {
      findings.add(
        VaultAuditFinding(
          item: item,
          issue: VaultAuditIssue.missingTwoFactor,
          detail: 'No authenticator code attached.',
        ),
      );
    }
  }

  findings.sort((a, b) {
    final byIssue = a.issue.index.compareTo(b.issue.index);
    if (byIssue != 0) return byIssue;
    return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
  });

  final counts = <VaultAuditIssue, int>{};
  var penalty = 0;
  for (final finding in findings) {
    counts[finding.issue] = (counts[finding.issue] ?? 0) + 1;
    penalty += finding.issue.weight;
  }

  final score = logins.isEmpty ? 100 : (100 - penalty).clamp(0, 100).toInt();

  return VaultAuditReport(
    findings: findings,
    logins: logins.length,
    score: score,
    counts: counts,
  );
}
