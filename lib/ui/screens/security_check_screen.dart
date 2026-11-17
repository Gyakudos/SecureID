import 'package:flutter/material.dart';

import '../../models/vault_item.dart';
import '../../security/vault_audit.dart';
import '../../state/vault_scope.dart';
import '../theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/item_detail_sheet.dart';

/// Offline health check for every login in the vault.
///
/// Everything is calculated on this device from the decrypted vault. Nothing is
/// uploaded, so the screen also works with no network connection.
class SecurityCheckScreen extends StatelessWidget {
  const SecurityCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final report = auditVault(controller.items);

    return Scaffold(
      appBar: AppBar(title: const Text('Security check')),
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ScoreCard(report: report),
                    const SizedBox(height: 18),
                    if (report.logins == 0)
                      const _MessageCard(
                        icon: Icons.playlist_add_rounded,
                        color: kAccent,
                        title: 'No logins to check',
                        message:
                            'Add a login to the vault and it will show up here '
                            'with any weak, reused or missing passwords.',
                      )
                    else if (report.isClean)
                      const _MessageCard(
                        icon: Icons.verified_user_rounded,
                        color: kMint,
                        title: 'No issues found',
                        message:
                            'Every login has a strong, unique password and a '
                            'two-factor code. Keep it that way.',
                      )
                    else ...[
                      for (final issue in VaultAuditIssue.values)
                        if (report.countOf(issue) > 0) ...[
                          _IssueSection(
                            issue: issue,
                            findings: report.findingsFor(issue),
                          ),
                          const SizedBox(height: 18),
                        ],
                    ],
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Checked offline on this device. SecureID never '
                            'sends your vault, passwords or audit results '
                            'anywhere.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final VaultAuditReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _scoreColor(report.score);
    final issues = report.findings.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 104,
                  height: 104,
                  child: CircularProgressIndicator(
                    value: report.score / 100,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${report.score}',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'out of 100',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SECURITY SCORE',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report.scoreLabel,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: color),
                ),
                const SizedBox(height: 8),
                Text(
                  '${report.logins} ${report.logins == 1 ? 'login' : 'logins'} '
                  'checked',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  issues == 0
                      ? 'Nothing to fix'
                      : '$issues ${issues == 1 ? 'issue' : 'issues'} found',
                  style: TextStyle(
                    color: issues == 0 ? kMint : scheme.onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueSection extends StatelessWidget {
  const _IssueSection({required this.issue, required this.findings});

  final VaultAuditIssue issue;
  final List<VaultAuditFinding> findings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _issueColor(issue, scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(_issueIcon(issue), size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                issue.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Text(
                '${findings.length}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          issue.summary,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < findings.length; index++) ...[
                if (index > 0) const Divider(height: 1),
                _FindingTile(finding: findings[index], color: color),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding, required this.color});

  final VaultAuditFinding finding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = finding.item;
    final title = item.title.trim().isEmpty ? 'Untitled login' : item.title;
    final account = item.username.trim();
    final subtitle = account.isEmpty
        ? finding.detail
        : '${finding.detail} · $account';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(_issueIcon(finding.issue), color: color),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: () {
        // Prefer the live item so the sheet reflects edits made since the
        // report was built.
        final controller = VaultScope.read(context);
        VaultItem? current;
        for (final candidate in controller.items) {
          if (candidate.id == item.id) {
            current = candidate;
            break;
          }
        }
        showItemDetailSheet(context, current ?? item);
      },
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _issueIcon(VaultAuditIssue issue) => switch (issue) {
  VaultAuditIssue.emptyPassword => Icons.key_off_rounded,
  VaultAuditIssue.weakPassword => Icons.speed_rounded,
  VaultAuditIssue.reusedPassword => Icons.copy_all_rounded,
  VaultAuditIssue.missingTwoFactor => Icons.gpp_maybe_rounded,
};

Color _issueColor(VaultAuditIssue issue, ColorScheme scheme) => switch (issue) {
  VaultAuditIssue.missingTwoFactor => kAccent,
  _ => scheme.error,
};

Color _scoreColor(int score) {
  if (score >= 90) return kMint;
  if (score >= 75) return kAccent;
  if (score >= 50) return const Color(0xFFFFB020);
  return kDanger;
}
