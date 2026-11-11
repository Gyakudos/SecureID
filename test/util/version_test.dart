import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/util/version.dart';

void main() {
  test('parses plain and tagged versions', () {
    expect(AppVersion.tryParse('1.2.3'), const AppVersion(1, 2, 3));
    expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
    expect(AppVersion.tryParse('V1.2.3'), const AppVersion(1, 2, 3));
    expect(AppVersion.tryParse(' 1.2.3 '), const AppVersion(1, 2, 3));
  });

  test('pads missing parts and drops build metadata', () {
    expect(AppVersion.tryParse('1.2'), const AppVersion(1, 2, 0));
    expect(AppVersion.tryParse('2'), const AppVersion(2, 0, 0));
    expect(AppVersion.tryParse('1.2.3+7'), const AppVersion(1, 2, 3));
  });

  test('ignores pre-release suffixes', () {
    expect(AppVersion.tryParse('1.2.3-beta.1'), const AppVersion(1, 2, 3));
    expect(AppVersion.tryParse('1.2.3-beta.1'), AppVersion.tryParse('1.2.3'));
  });

  test('rejects unusable input', () {
    expect(AppVersion.tryParse(null), isNull);
    expect(AppVersion.tryParse(''), isNull);
    expect(AppVersion.tryParse('latest'), isNull);
    expect(AppVersion.tryParse('1.2.3.4'), isNull);
    expect(AppVersion.tryParse('1.x.3'), isNull);
    expect(AppVersion.tryParse('-1.2.3'), isNull);
  });

  test('orders by major, then minor, then patch', () {
    expect(
      AppVersion.tryParse('1.2.3')! > AppVersion.tryParse('1.2.2')!,
      isTrue,
    );
    expect(
      AppVersion.tryParse('1.3.0')! > AppVersion.tryParse('1.2.9')!,
      isTrue,
    );
    expect(
      AppVersion.tryParse('2.0.0')! > AppVersion.tryParse('1.9.9')!,
      isTrue,
    );
    expect(
      AppVersion.tryParse('1.0.0')! > AppVersion.tryParse('1.0.0')!,
      isFalse,
    );
    expect(
      AppVersion.tryParse('1.0.0')! >= AppVersion.tryParse('1.0.0')!,
      isTrue,
    );
    expect(
      AppVersion.tryParse('1.0.0')! < AppVersion.tryParse('1.0.1')!,
      isTrue,
    );
  });

  test('equals and hashes by value', () {
    final a = AppVersion.tryParse('v1.2.3');
    final b = AppVersion.tryParse('1.2.3+9');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), '1.2.3');
  });
}
