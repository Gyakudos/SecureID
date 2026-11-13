import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/services/password_import.dart';

void main() {
  group('CSV format detection', () {
    test('reads a quoted Chrome export with a multi-line note', () {
      final result = PasswordCsvImport.parse(
        'name,url,username,password,note\n'
        '"Example, Inc.",https://example.com/login,alice@example.com,'
        '"p@ss,word","line one\nline two"\n',
      );

      expect(result.format, ImportFormat.chromium);
      expect(result.count, 1);
      expect(result.skippedRows, 0);
      final item = result.items.single;
      expect(item.title, 'Example, Inc.');
      expect(item.url, 'https://example.com/login');
      expect(item.username, 'alice@example.com');
      expect(item.password, 'p@ss,word');
      expect(item.notes, 'line one\nline two');
    });

    test('detects the Edge export, which shares Chrome columns', () {
      final result = PasswordCsvImport.parse(
        'name,url,username,password,note\n'
        'Outlook,https://outlook.com,me@example.com,secret,\n',
      );

      expect(result.format, ImportFormat.chromium);
      expect(result.items.single.title, 'Outlook');
    });

    test('reads Safari columns and an OTPAuth secret', () {
      final result = PasswordCsvImport.parse(
        'Title,URL,Username,Password,Notes,OTPAuth\n'
        'GitHub,https://github.com,octocat,secret,Recovery codes,'
        'otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub'
        '&digits=6&period=30\n',
      );

      expect(result.format, ImportFormat.safari);
      final item = result.items.single;
      expect(item.title, 'GitHub');
      expect(item.username, 'octocat');
      expect(item.notes, 'Recovery codes');
      expect(item.totp, isNotNull);
      expect(item.totp!.secret, 'JBSWY3DPEHPK3PXP');
      expect(item.totp!.issuer, 'GitHub');
      expect(item.totp!.accountName, 'octocat');
      expect(item.totp!.digits, 6);
      expect(item.totp!.period, 30);
    });

    test('reads Bitwarden folders, favourites and a plain TOTP secret', () {
      final result = PasswordCsvImport.parse(
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
        'login_username,login_password,login_totp\n'
        'Work,1,login,GitLab,note,,0,https://gitlab.com,bob,pw,'
        'JBSWY3DPEHPK3PXP\n',
      );

      expect(result.format, ImportFormat.bitwarden);
      final item = result.items.single;
      expect(item.title, 'GitLab');
      expect(item.username, 'bob');
      expect(item.password, 'pw');
      expect(item.favorite, isTrue);
      expect(item.tags, contains('Work'));
      expect(item.totp, isNotNull);
      expect(item.totp!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('imports a Bitwarden secure note without credentials', () {
      final result = PasswordCsvImport.parse(
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
        'login_username,login_password,login_totp\n'
        ',0,note,WiFi codes,home wifi,,,,,\n',
      );

      expect(result.format, ImportFormat.bitwarden);
      final item = result.items.single;
      expect(item.title, 'WiFi codes');
      expect(item.notes, 'home wifi');
      expect(item.username, isEmpty);
      expect(item.password, isEmpty);
    });

    test('skips Bitwarden cards and identities', () {
      final result = PasswordCsvImport.parse(
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
        'login_username,login_password,login_totp\n'
        ',0,card,Visa,,,,\n'
        ',0,identity,Passport,,,,\n'
        'Work,0,login,Example,,,0,https://example.com,user,pw,\n',
      );

      expect(result.count, 1);
      expect(result.skippedRows, 2);
      expect(result.items.single.title, 'Example');
    });

    test('reads a LastPass export with grouping and extra notes', () {
      final result = PasswordCsvImport.parse(
        'url,username,password,totp,extra,name,grouping,fav\n'
        'https://example.org,user,pw,,extra notes,Example,Personal,1\n',
      );

      expect(result.format, ImportFormat.lastPass);
      final item = result.items.single;
      expect(item.title, 'Example');
      expect(item.notes, 'extra notes');
      expect(item.tags, contains('Personal'));
      expect(item.favorite, isTrue);
    });

    test('reads a 1Password export with tags and favourites', () {
      final result = PasswordCsvImport.parse(
        'Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes\n'
        'Bank,https://bank.example,me,pw,,true,false,Finance,note\n',
      );

      expect(result.format, ImportFormat.onePassword);
      final item = result.items.single;
      expect(item.title, 'Bank');
      expect(item.favorite, isTrue);
      expect(item.tags, contains('Finance'));
      expect(item.notes, 'note');
    });

    test('reads a Dashlane export', () {
      final result = PasswordCsvImport.parse(
        'username,username2,username3,title,password,note,url,category,'
        'otpSecret\n'
        'me,,,Mail,pw,note,https://mail.example,Personal,'
        'JBSWY3DPEHPK3PXP\n',
      );

      expect(result.format, ImportFormat.dashlane);
      final item = result.items.single;
      expect(item.title, 'Mail');
      expect(item.tags, contains('Personal'));
      expect(item.totp!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('reads a KeePass export', () {
      final result = PasswordCsvImport.parse(
        'Account,Login Name,Password,Web Site,Comments\n'
        'Router,admin,pw,https://192.168.1.1,LAN\n',
      );

      expect(result.format, ImportFormat.keepass);
      final item = result.items.single;
      expect(item.title, 'Router');
      expect(item.username, 'admin');
      expect(item.url, 'https://192.168.1.1');
      expect(item.notes, 'LAN');
    });

    test('falls back to generic columns', () {
      final result = PasswordCsvImport.parse(
        'Title,URL,Username,Password\n'
        'Generic,https://generic.example,u,p\n',
      );

      expect(result.format, ImportFormat.generic);
      expect(result.items.single.title, 'Generic');
    });
  });

  group('CSV edge cases', () {
    test('handles escaped quotes and embedded delimiters', () {
      final result = PasswordCsvImport.parse(
        'name,url,username,password,note\n'
        '"Quote ""test""",https://q.example,u,p,"a,b,c"\n',
      );

      final item = result.items.single;
      expect(item.title, 'Quote "test"');
      expect(item.notes, 'a,b,c');
    });

    test('handles semicolon-delimited exports', () {
      final result = PasswordCsvImport.parse(
        'name;url;username;password\n'
        'Example;https://example.com;user;pw\n',
      );

      expect(result.format, ImportFormat.chromium);
      expect(result.items.single.username, 'user');
    });

    test('skips duplicate rows inside the same file', () {
      final result = PasswordCsvImport.parse(
        'name,url,username,password,note\n'
        'Example,https://example.com,user,pw,\n'
        'Example,https://example.com,user,pw,\n',
      );

      expect(result.count, 1);
      expect(result.skippedRows, 1);
    });

    test('reads headerless Chrome order', () {
      final result = PasswordCsvImport.parse(
        'Example,https://example.com,user,pw,note\n',
      );

      expect(result.hasHeader, isFalse);
      expect(result.format, ImportFormat.chromium);
      final item = result.items.single;
      expect(item.title, 'Example');
      expect(item.url, 'https://example.com');
      expect(item.username, 'user');
      expect(item.password, 'pw');
      expect(result.warnings, isNotEmpty);
    });

    test('returns a warning for an empty file', () {
      final result = PasswordCsvImport.parse('   \n');

      expect(result.count, 0);
      expect(result.warnings, isNotEmpty);
    });

    test('keeps extra URLs in the notes', () {
      final result = PasswordCsvImport.parse(
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
        'login_username,login_password,login_totp\n'
        ',0,login,Multi,,,0,"https://a.example https://b.example",u,p,\n',
      );

      final item = result.items.single;
      expect(item.url, 'https://a.example');
      expect(item.notes, contains('Other URLs:'));
      expect(item.notes, contains('https://b.example'));
    });
  });
}
