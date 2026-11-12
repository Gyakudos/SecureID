const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int value) => value.toString().padLeft(2, '0');

String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

String formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${formatDate(local)} · ${_two(local.hour)}:${_two(local.minute)}';
}

/// A short "time since" label for lists and device rows.
String formatRelative(DateTime value, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final difference = current.difference(value.toLocal());
  if (difference.isNegative || difference.inSeconds < 45) return 'just now';
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays} d ago';
  }
  return formatDate(value);
}

String formatBackupStamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year}${_two(local.month)}${_two(local.day)}'
      '-${_two(local.hour)}${_two(local.minute)}';
}
