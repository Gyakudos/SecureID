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

String formatBackupStamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year}${_two(local.month)}${_two(local.day)}'
      '-${_two(local.hour)}${_two(local.minute)}';
}
