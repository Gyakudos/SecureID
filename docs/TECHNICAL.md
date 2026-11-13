# SecureID

SecureID is a standalone, local-first vault for passwords, passkeys and
authenticator codes. It runs on **Windows** and **Android** and stores
everything in a single encrypted file on the device.

An optional **Supabase account** can sync the already-encrypted vault between
devices. The master password and every secret stay on the device; the server
only stores the sealed envelope. Without an account, the app works fully
offline. If you lose the master password, the only way back in is a backup you
exported earlier.

## Features

- **Logins** — title, username, password, website, notes and tags, plus an
  optional **2FA** secret shown inline on the login card.
- **Passkeys** — relying party, account, credential ID, user handle, COSE
  public key, algorithm, signature counter, AAGUID and discoverability.
- **Authenticator** — live 6–8 digit TOTP codes with a countdown ring.
  - Attach a secret to a login, or add a standalone authenticator entry.
  - Import `otpauth://totp/...` links by pasting them on any platform.
  - Scan enrollment QR codes with the Android camera.
  - SHA-1, SHA-256 and SHA-512, with 30 s or 60 s periods.
- **Password generator** — length, character classes and ambiguous-character
  exclusion, with a strength estimate.
- **Search and filters** — all items, logins, passkeys, 2FA codes and
  favorites.
- **Auto-lock** — after inactivity and/or when the app is backgrounded.
- **Secure clipboard** — copied secrets are cleared after a configurable delay.
- **Device unlock** — optional Windows Hello (PIN, fingerprint or face) on
  Windows, and biometric unlock on Android. The vault key is wrapped by a
  device-bound key, and the master password always remains valid.
- **Default Login** — choose what the lock screen asks for first. On Windows the
  choices are Password and Windows Hello; on Android they are Password,
  Biometrics and Password Style. The master password always stays available.
- **Password Style (Android)** — unlock with a six-digit PIN on a phone-style
  0-9 pad, or a drawn 3x3 pattern that connects at least four dots. The
  PIN/pattern wraps the vault key and falls back to the master password after
  five wrong attempts.
- **Optional account sync** — email/password sign-in with Supabase. Only the
  encrypted vault envelope is uploaded, with per-user row-level security and
  revision-based conflict detection.
- **Linked phone** — move the encrypted vault between Windows and Android over
  the local network with a one-time QR code. Works fully offline, with no
  account and no internet connection.
- **Trusted devices** — pair a phone and a PC once by scanning a QR code, then
  send the encrypted vault with one tap per side. The trust key is sealed with
  DPAPI on Windows or the Android Keystore, and only authorises transport: the
  master password is still required to decrypt. Works fully offline.
- **Linked devices** — when signed in, the account screen lists every device
  that has synced, with its platform and last-seen time.
- **Encrypted backups** — export and restore the sealed vault file.
- **Password import** — read CSV exports from Chrome, Edge, Safari, Firefox,
  Bitwarden, LastPass, 1Password, Dashlane, KeePass and NordPass. On Windows,
  read Chrome, Edge, Brave, Vivaldi, Chromium and Opera profiles directly and
  decrypt their saved passwords locally. Profiles protected by app-bound
  encryption fall back to the browser's own CSV export.
- **Vision accessibility** — larger text (up to 200%), a high-contrast theme,
  screen-reader labels, and spoken account summaries and details. The controls
  are available on the setup and unlock screens too, before the vault opens.
- **Update check** — the version pill on the vault screen and the
  **Check for updates** row in Settings query the public GitHub releases API
  for a newer version, then link straight to the matching installer or APK.
  It only runs when you ask, and sends no vault, account or device data.
- **FLAG_SECURE on Android** — the vault is hidden from screenshots and the
  recent-apps thumbnail.

## Vision accessibility

Open **Vision & reading** from the unlock screen, the setup screen, or
**Settings**. The preferences are stored in `accessibility.json` next to the
vault, outside the encrypted envelope, so they apply before unlock.

- **Text size** scales the whole app on top of the system text-size setting.
- **Read accounts aloud** uses the device's installed text-to-speech voice. The
  speaker button on the vault screen reads every visible account, and each card
  has its own read button. Passwords and authenticator secrets are never read in
  a summary; **Read full details aloud** on an item sheet is explicit.
- **High contrast** switches to a pure-black background with brighter text and
  borders.

Text-to-speech runs locally through the Windows and Android system voices; no
account text is sent to a network service.

## Keyboard shortcuts (Windows)

| Shortcut | Action |
| --- | --- |
| `Ctrl+N` | Add an item |
| `Ctrl+F` | Focus search |
| `Ctrl+L` | Lock the vault |

## Security model

```
master password ──Argon2id(19 MiB, 2 iterations, random 16-byte salt)──► 256-bit key
                                                                          │
vault JSON ──────────────────────────────AES-256-GCM (random 12-byte nonce)┘
```

- The on-disk envelope contains only the KDF parameters, salt and ciphertext.
- Every save uses a fresh nonce. The envelope is written atomically with a
  `.bak` rotation so a crash cannot leave a half-written vault.
- The vault file lives in the platform application-support folder:
  - Windows: `%APPDATA%\com.local\secure_id\vault.json`
  - Android: the app's private support directory.
- Device unlock stores the vault key wrapped with a device-bound key: DPAPI on
  Windows, and an Android Keystore key that can only be used after a biometric
  prompt on Android. It never stores the master password.
- PIN/pattern quick unlock derives a wrapping key with Argon2id (64 MiB,
  3 iterations) and AES-256-GCM, then stores only the wrapped vault key in
  `vault.quick.json`. Five wrong attempts force the master password. Changing
  the master password removes the record, because the vault key changes and
  cannot be rewrapped without the PIN or pattern.
- The chosen default login lives in `login.json` outside the vault, because the
  lock screen needs it before the vault is open and it describes this device
  rather than the synced vault.
- `vault.pin.json`, `vault.quick.json`, `login.json` and `accessibility.json`
  sit next to `vault.json` and contain no plaintext secrets.
- Passkey records hold **public metadata only**. SecureID is not an OS passkey
  provider; the private key stays in the authenticator that created it.
- Account sync is zero-knowledge: the server receives the same encrypted
  envelope that is written to disk, plus a SHA-256 hash and revision number.
  The master password is never sent to Supabase.
- Sync uses compare-and-swap on the revision number. If both the local and
  account vaults changed, the app asks whether to keep this device's version or
  use the account version instead of silently overwriting either one.
- Row-level security limits every `vaults` row to its owner (`auth.uid()`).
- Linked-phone transfer never decrypts the vault. The sending device serves the
  same encrypted envelope over plain HTTP on the local network, protected by a
  random single-use token that expires after 10 minutes. The receiving device
  still needs the master password to open it.
- The `devices` table stores only a random device id, display name, platform and
  timestamps. It is a directory, not a key store, and is scoped by row-level
  security.

## Project layout

```
lib/
  config/       build-time Supabase configuration
  models/       vault items, passkeys, TOTP data, settings, device login
  security/     Argon2id + AES-GCM, TOTP, password generator, device unlock, quick unlock
  services/     account auth, remote vault storage, LAN pairing, password import, device registry, speech
  state/        VaultController and the inherited VaultScope
  storage/      atomic file storage for the vault, sync state, identity, unlock records, login prefs and accessibility prefs
  ui/           screens, scanner and shared widgets
supabase/       SQL schema and setup guide for optional account sync
test/           crypto, RFC 6238 vectors, models, controller, sync and widget tests
tools/          icon generation and desktop shortcut scripts
installer/      NSIS script and build wrapper for the Windows installer
```

## Building

Flutter 3.47+ with the Windows desktop toolchain or the Android SDK is
required. The Windows build also needs `nuget.exe` on `PATH` because the
`flutter_tts` plugin fetches its C++/WinRT dependency through NuGet. This
repository keeps a copy at `tools\nuget.exe`; the installer wrapper adds it to
`PATH` automatically.

```powershell
flutter pub get

# Windows
flutter build windows --release

# Android (release APK, signed with the debug key by default)
flutter build apk --release
```

The Windows executable is written to
`build\windows\x64\runner\Release\secure_id.exe`.

### Windows installer

The installer is built with [NSIS](https://nsis.sourceforge.io/). Install it
once, then build the app and the setup executable:

```powershell
winget install --id NSIS.NSIS -e
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1 -BuildFirst
```

The result is `dist\SecureID-Setup-1.2.52.exe`. It is a per-user installer: it
does **not** require administrator rights and installs to
`%LOCALAPPDATA%\Programs\SecureID`. It bundles the Flutter engine and every
runtime DLL, so the target machine does not need Flutter installed. It creates
Desktop and Start Menu shortcuts and registers an uninstaller in **Apps &
Features**. Uninstalling never deletes the encrypted vault in `%APPDATA%`.

To compile account sync into the installed build, pass the public Supabase
credentials to the same script:

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1 `
  -BuildFirst `
  -SupabaseUrl https://YOUR-PROJECT.supabase.co `
  -SupabaseKey YOUR-PUBLIC-ANON-OR-PUBLISHABLE-KEY
```

The installer is unsigned, so Windows SmartScreen may show a warning on other
machines. Sign it with an Authenticode certificate for public distribution.

### Enabling account sync

Account sync is compiled in only when Supabase credentials are supplied at
build time. The app remains fully usable offline without them.

```powershell
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLIC-ANON-OR-PUBLISHABLE-KEY
```

Use the public anon/publishable key, never the `service_role` key. Create the
`vaults` table and its row-level security policies with
[`supabase/schema.sql`](supabase/schema.sql); the full walkthrough is in
[`supabase/README.md`](supabase/README.md).

### Linking a phone

No account or internet connection is required.

1. On the device that already has the vault, open **Settings → Linked phone →
   Link a phone → Send from this device**.
2. On the other device, open **Settings → Linked phone → Link a phone → Receive
   from a device**, then scan the QR code (Android) or paste the copied link
   (Windows).
3. The receiving device downloads the encrypted envelope and asks for the
   master password to unlock it.

Both devices must be on the same Wi-Fi or LAN. The link is single-use and
expires after 10 minutes. On Windows, allow the app through the firewall if
prompted. Receiving a vault replaces any vault already on the receiving device,
so export a backup first if needed.

### Trusted devices

Trusted devices turn the one-time link into a repeatable, one-tap transfer.
Pairing happens once; both sides then remember each other. The trusted list and
the pairing flow are separate screens, so adding a phone never removes the
devices already trusted.

1. On the PC, open **Settings → Linked devices → Pair a new Device**. The PC
   shows a QR code and a six-digit code.
2. On the phone, open **Trusted Devices → Pair a new Device** and scan the
   code. Check that the six digits match the PC screen, then confirm.
3. The phone sends the encrypted envelope in the same scan. The PC asks once
   before pairing and replacing an existing vault.

Later transfers need no QR code, and either side can push an update:

1. Open **Trusted Devices** on the sending device.
2. Tap **Send** on the paired device. If it is not already listening, open
   **Receive updates** on the receiving device first. The receiver confirms
   unless **Accepts automatically** is enabled for that device.

Pairing a vault that is already on this device keeps its local login settings.
Windows Hello, the PIN/pattern quick unlock and the chosen default login keep
working because the device-wrapped key still belongs to the same vault
identity (salt and KDF parameters). Receiving a different vault removes the
stale key record but keeps the platform device key and the login preferences;
on Windows the record is recreated silently after the next master-password
unlock, and Android asks for a biometric confirmation before re-enabling it.

Both devices must be on the same Wi-Fi or LAN. The receiver prefers TCP port
`47824` and announces itself over UDP port `47823`; if the port is busy it
falls back to an ephemeral one, and discovery corrects the remembered address.
If discovery is blocked, the last known stable address is used. Allow the app
through the Windows firewall if prompted.

Pairing uses X25519, with the shared secret mixed through HKDF-SHA256 with a
random 32-byte pairing secret that travels only inside the QR code. Both sides
prove the derived keys with an HMAC transcript, and the six-digit code makes a
replaced QR visible. Vault envelopes are sealed with AES-256-GCM under the
derived trust key, with associated data binding the session and both device
ids. Pairing codes are single-use and expire after five minutes; the receiver
also rate-limits failed attempts and keeps a replay cache.

The trust key is stored in `trusted_devices.bin`, sealed by DPAPI for the
current Windows user or by a non-authentication AES-256-GCM key in the Android
Keystore. It is deliberately outside the vault so a locked PC or a fresh setup
can still receive. It can never decrypt the vault. Forget a device in the list
to revoke its access immediately without affecting the other devices.

### Importing passwords

Open **Settings → Import passwords**. The screen offers two routes and keeps
everything on the device:

- **CSV file** — SecureID parses the file itself, including quoted fields,
  embedded commas and multi-line notes. It recognises the column layouts used
  by Chrome and Edge (`name,url,username,password,note`), Safari and Apple
  Passwords (`Title,URL,Username,Password,Notes,OTPAuth`), Firefox, Bitwarden,
  LastPass, 1Password, Dashlane, KeePass and NordPass, and falls back to a
  generic resolver for recognisable headings. Folders become tags, favourites
  are preserved, `otpauth://` links and plain Base32 secrets become 2FA
  entries, and duplicate rows are collapsed. Before importing, the screen shows
  the detected format, the number of logins, skipped rows and any warnings.
  Existing vault entries are skipped by default; the switch can import them
  again instead.
- **Direct browser import (Windows)** — SecureID looks for Chrome, Edge,
  Brave, Vivaldi, Chromium and Opera profiles, copies the SQLite `Login Data`
  file to a private temporary directory, and reads the `logins` table. The
  AES-256 key in `Local State` is unsealed with DPAPI for the current Windows
  user, and each `v10`/`v11` value is decrypted with AES-256-GCM. The
  temporary copy is deleted afterwards. Safari has no Windows build, so its
  CSV export is the supported route there.

Chrome and Edge can protect newer passwords with app-bound encryption (`v20`).
Windows deliberately prevents another process from unwrapping that key, so
SecureID counts those rows and tells you to use the browser's own CSV export
instead of pretending the import succeeded. The same applies if the browser is
holding an exclusive lock on the database; close it and retry.

Imported entries are ordinary vault logins: they are encrypted with the vault
key in the next save and inherit the same search, 2FA, clipboard and backup
behaviour. Delete the source CSV afterwards because it contains plaintext
passwords.

### Desktop shortcut

After building, create a shortcut on the current user's desktop:

```powershell
powershell -ExecutionPolicy Bypass -File tools\create_shortcut.ps1
```

### Regenerating the icon

The launcher icon is generated from code, so it can be recreated at any time:

```powershell
powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1
```

This writes `windows/runner/resources/app_icon.ico` and the Android
`mipmap-*/ic_launcher.png` files.

## Tests

```powershell
flutter analyze
flutter test
```

The suite covers the Argon2id/AES-GCM envelope, tamper detection, RFC 6238 TOTP
vectors for all three hash algorithms, `otpauth` parsing, password generation
and strength, model round-trips, the full controller lifecycle (including
Windows Hello, Android biometrics, PIN/pattern quick unlock, default login and
backup restore), account sign-in, upload/download sync, conflict detection and
resolution, accessibility preferences and spoken summaries, trusted-device
pairing, sealed trust-store persistence, trusted transfer/replay rejection,
CSV format detection and quoting, Chromium password decryption and direct
database import, import duplicate handling, and the setup/unlock widget flows.

## Limitations

- Device unlock needs an enrolled Windows Hello PIN/biometric or an Android
  fingerprint or face. Android requires a strong (Class 3) biometric for the
  Keystore key; without one, the master password is used.
- Enrolling a new fingerprint or face invalidates the Android Keystore key, so
  biometric unlock must be enabled again with the master password.
- Password Style quick unlock is Android-only; Windows uses Windows Hello as
  its non-password option. A six-digit PIN has limited entropy, so the Argon2id
  cost and five-attempt limit are the protections.
- QR scanning uses `mobile_scanner`, which has no Windows implementation, so
  desktop users paste `otpauth://` links or type the Base32 secret.
- SecureID does not register itself as a platform passkey provider. Passkey
  entries are an encrypted inventory of credential metadata, not a sign-in
  mechanism.
- There is no password recovery. Export a backup and keep the master password
  somewhere safe.
- Account sync needs a Supabase project and build-time credentials. Whether new
  accounts must confirm their email depends on the project's email settings.
- Sync stores the vault as one row. Extremely large vaults should move the
  encrypted envelope to object storage instead.
- The update check needs a network connection. It reads the public GitHub
  releases API unauthenticated, so it is subject to GitHub's rate limit; a
  failure is reported in place and never blocks the vault.
