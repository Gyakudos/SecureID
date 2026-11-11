import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vault_item.dart';
import '../../state/vault_controller.dart';
import '../../state/vault_scope.dart';
import '../../util/date_format.dart';
import '../../util/speech_text.dart';
import '../theme.dart';
import '../widgets/add_item_sheet.dart';
import '../widgets/brand_mark.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/gradient_background.dart';
import '../widgets/item_detail_sheet.dart';
import '../widgets/totp_display.dart';
import '../widgets/update_dialog.dart';
import 'account_screen.dart';
import 'item_editor_screen.dart';
import 'settings_screen.dart';

enum _VaultFilter { all, logins, passkeys, totp, favorites }

extension on _VaultFilter {
  String get label => switch (this) {
    _VaultFilter.all => 'All',
    _VaultFilter.logins => 'Logins',
    _VaultFilter.passkeys => 'Passkeys',
    _VaultFilter.totp => '2FA',
    _VaultFilter.favorites => 'Favorites',
  };

  bool matches(VaultItem item) => switch (this) {
    _VaultFilter.all => true,
    _VaultFilter.logins => item.isLogin,
    _VaultFilter.passkeys => item.isPasskey,
    _VaultFilter.totp => item.hasTotp,
    _VaultFilter.favorites => item.favorite,
  };
}

class VaultHomeScreen extends StatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  _VaultFilter _filter = _VaultFilter.all;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<VaultItem> _visibleItems(VaultController controller) {
    final items = controller.items
        .where(_filter.matches)
        .where((item) => item.matches(_query))
        .toList(growable: true);
    items.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      if (byTitle != 0) return byTitle;
      return a.createdAt.compareTo(b.createdAt);
    });
    return items;
  }

  Future<void> _addItem() async {
    final kind = await showAddItemSheet(context);
    if (kind == null || !mounted) return;
    final item = switch (kind) {
      VaultItemKind.login => VaultItem.newLogin(),
      VaultItemKind.passkey => VaultItem.newPasskey(),
      VaultItemKind.totp => VaultItem.newTotp(),
    };
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ItemEditorScreen(item: item)),
    );
  }

  Future<void> _editItem(VaultItem item) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ItemEditorScreen(item: item.copy())),
    );
  }

  Future<void> _deleteItem(VaultItem item) async {
    final controller = VaultScope.read(context);
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${item.title}?',
      message:
          'This item will be removed from the encrypted vault. '
          'This cannot be undone unless you have a backup.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await controller.deleteItem(item.id);
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountScreen()));
  }

  IconData _accountIcon(VaultController controller) {
    return switch (controller.syncStatus) {
      SyncStatus.syncing => Icons.cloud_sync_rounded,
      SyncStatus.conflict => Icons.sync_problem_rounded,
      SyncStatus.error => Icons.cloud_off_rounded,
      SyncStatus.signedOut => Icons.cloud_off_rounded,
      SyncStatus.disabled => Icons.cloud_off_rounded,
      SyncStatus.idle =>
        controller.isSignedIn
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_rounded,
    };
  }

  Color _accountColor(VaultController controller) {
    return switch (controller.syncStatus) {
          SyncStatus.syncing => kAccent,
          SyncStatus.conflict => kDanger,
          SyncStatus.error => kDanger,
          SyncStatus.idle => controller.isSignedIn ? kMint : null,
          _ => null,
        } ??
        Theme.of(context).colorScheme.onSurfaceVariant;
  }

  String _accountTooltip(VaultController controller) {
    return switch (controller.syncStatus) {
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.conflict => 'Sync needs attention',
      SyncStatus.error => 'Sync failed',
      SyncStatus.idle =>
        controller.isSignedIn ? 'Account & sync' : 'Sign in to sync',
      _ => 'Sign in to sync',
    };
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = VaultScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = _visibleItems(controller);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _addItem,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            controller.lock,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addItem,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add item'),
          ),
          body: GradientBackground(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                        child: Row(
                          children: [
                            const BrandMark(size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 2,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'SecureID',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(letterSpacing: -0.3),
                                      ),
                                      _VersionBadge(
                                        version: controller.currentVersion,
                                        updateAvailable:
                                            controller.updateAvailable,
                                        onTap: () => showUpdateCheck(context),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    '${controller.items.length} items · '
                                    '${controller.totpCount} codes · '
                                    'saved ${controller.lastSavedAt == null ? 'just now' : formatDateTime(controller.lastSavedAt!)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (controller.speechAvailable)
                              IconButton(
                                tooltip: controller.isSpeaking
                                    ? 'Stop reading'
                                    : 'Read accounts aloud',
                                onPressed: controller.isSpeaking
                                    ? controller.stopSpeaking
                                    : () =>
                                          controller.speak(itemsSpeech(items)),
                                icon: Icon(
                                  controller.isSpeaking
                                      ? Icons.stop_circle_outlined
                                      : Icons.volume_up_rounded,
                                ),
                              ),
                            if (controller.accountAvailable)
                              IconButton(
                                tooltip: _accountTooltip(controller),
                                onPressed: _openAccount,
                                icon: Icon(
                                  _accountIcon(controller),
                                  color: _accountColor(controller),
                                ),
                              ),
                            IconButton(
                              tooltip: 'Settings (Ctrl+,)',
                              onPressed: _openSettings,
                              icon: const Icon(Icons.settings_rounded),
                            ),
                            IconButton(
                              tooltip: 'Lock vault (Ctrl+L)',
                              onPressed: controller.lock,
                              icon: const Icon(Icons.lock_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          onChanged: (value) => setState(() => _query = value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search titles, accounts, tags…',
                            prefixIcon: const Icon(Icons.search_rounded),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _search.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final filter in _VaultFilter.values) ...[
                                ChoiceChip(
                                  label: Text(filter.label),
                                  selected: _filter == filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: items.isEmpty
                            ? _EmptyState(
                                query: _query,
                                filter: _filter,
                                onAdd: _addItem,
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  120,
                                ),
                                itemCount: items.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return _VaultItemCard(
                                    item: item,
                                    onTap: () =>
                                        showItemDetailSheet(context, item),
                                    onEdit: () => _editItem(item),
                                    onDelete: () => _deleteItem(item),
                                    onFavorite: () =>
                                        controller.toggleFavorite(item.id),
                                    onRead: controller.speechAvailable
                                        ? () =>
                                              controller.speak(itemSpeech(item))
                                        : null,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultItemCard extends StatelessWidget {
  const _VaultItemCard({
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onFavorite,
    this.onRead,
  });

  final VaultItem item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (item.kind) {
      VaultItemKind.login => (Icons.language_rounded, kAccent),
      VaultItemKind.passkey => (Icons.key_rounded, kMint),
      VaultItemKind.totp => (
        Icons.shield_moon_rounded,
        const Color(0xFFFFC46B),
      ),
    };
    final title = item.title.isEmpty ? item.kind.label : item.title;

    return Semantics(
      label: itemSpeech(item),
      container: true,
      child: Material(
        color: scheme.surfaceContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title.isEmpty ? item.kind.label : item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                      if (item.hasTotp) ...[
                        const SizedBox(height: 7),
                        TotpCodeView(data: item.totp!, compact: true),
                      ],
                    ],
                  ),
                ),
                if (onRead != null)
                  IconButton(
                    tooltip: 'Read $title aloud',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRead,
                    icon: Icon(
                      Icons.volume_up_rounded,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                IconButton(
                  tooltip: item.favorite ? 'Unfavorite' : 'Favorite',
                  visualDensity: VisualDensity.compact,
                  onPressed: onFavorite,
                  icon: Icon(
                    item.favorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 19,
                    color: item.favorite ? kMint : scheme.onSurfaceVariant,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_rounded, size: 18),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: kDanger,
                        ),
                        title: Text('Delete', style: TextStyle(color: kDanger)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small version pill. Tapping it opens the GitHub update check, so the
/// version number and the update button are the same affordance.
class _VersionBadge extends StatelessWidget {
  const _VersionBadge({
    required this.version,
    required this.onTap,
    this.updateAvailable = false,
  });

  final String version;
  final VoidCallback onTap;
  final bool updateAvailable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = updateAvailable ? kMint : scheme.onSurfaceVariant;

    return Tooltip(
      message: updateAvailable
          ? 'Version $version - update available'
          : 'Version $version - check for updates',
      child: Semantics(
        button: true,
        label: 'Version $version. Check for updates.',
        child: Material(
          color: updateAvailable
              ? kMint.withValues(alpha: 0.16)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          shape: StadiumBorder(
            side: BorderSide(
              color: updateAvailable
                  ? kMint.withValues(alpha: 0.55)
                  : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (updateAvailable) ...[
                    Icon(
                      Icons.arrow_circle_up_rounded,
                      size: 12,
                      color: foreground,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    'v$version',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.query,
    required this.filter,
    required this.onAdd,
  });

  final String query;
  final _VaultFilter filter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, title, body) = switch ((query.isNotEmpty, filter)) {
      (true, _) => (
        Icons.search_off_rounded,
        'No matches',
        'Nothing in your vault matches "$query".',
      ),
      (false, _VaultFilter.favorites) => (
        Icons.star_outline_rounded,
        'No favorites yet',
        'Tap the star on an item to pin it here.',
      ),
      (false, _VaultFilter.passkeys) => (
        Icons.key_rounded,
        'No passkeys stored',
        'Add a passkey record to keep its metadata backed up.',
      ),
      (false, _VaultFilter.totp) => (
        Icons.shield_moon_rounded,
        'No 2FA codes yet',
        'Add an authenticator secret to a login and its live code appears '
            'right on the card.',
      ),
      _ => (
        Icons.lock_outline_rounded,
        'Your vault is empty',
        'Add a login, a passkey or a standalone authenticator code to get '
            'started.',
      ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (query.isEmpty && filter == _VaultFilter.all) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add your first item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
