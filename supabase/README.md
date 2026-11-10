# SecureID account sync (Supabase)

SecureID can sync one **already-encrypted** vault between devices. Supabase is
used for three things only:

1. Email/password authentication.
2. Storing the encrypted `vault.json` envelope in the `vaults` table.
3. A directory of linked devices in the `devices` table (name, platform and
   last-seen time only).

The master password, the Argon2id key and all plaintext secrets stay on the
device. The server cannot decrypt anything it stores.

## 1. Create the project

1. Create a project at <https://supabase.com>.
2. Open **SQL Editor**, paste the contents of [`schema.sql`](schema.sql) and run
   it. This creates the `vaults` and `devices` tables and their per-user
   row-level security policies.
3. Open **Authentication → Providers → Email** and decide whether to require
   email confirmation:
   - **Confirmation off**: creating an account signs the user in immediately.
   - **Confirmation on** (default): the app asks the user to confirm by email
     before signing in. This is the safer choice for a real deployment.

## 2. Get the public credentials

Open **Project Settings → API** and copy:

- **Project URL**, for example `https://abcdefgh.supabase.co`
- The **anon** key or the newer **publishable** key

Both keys are public client keys protected by row-level security. **Never put
the `service_role` key in the app.**

## 3. Build with the credentials

Pass the values at build time. They are compiled into the app, which is fine
for public anon/publishable keys.

### Windows

```powershell
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLIC-KEY
```

### Android

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLIC-KEY
```

For development:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR-PUBLIC-KEY
```

Without these defines SecureID still runs normally as a fully offline vault;
the account screens explain that sync is not configured.

## How sync behaves

- The first device that signs in uploads its encrypted envelope.
- A new device signs in, downloads the envelope and asks for the master password
  to unlock it.
- Each save is followed by a debounced sync. There is also a **Sync now** button.
- Every upload is a compare-and-swap on a revision number, so two devices cannot
  silently overwrite each other.
- If both sides changed since the last sync, the app shows a conflict and asks
  whether to **keep this device** or **use the account version**.
- Changing the master password re-encrypts the vault with a new salt. Other
  devices will need the new master password after they download it.
- Signing out never deletes the local vault.

## Database notes

- `user_id` is the primary key: one vault row per account.
- `envelope` is the complete encrypted `vault.json` file.
- `content_hash` is a SHA-256 of the envelope, used only to detect whether the
  local and remote copies differ.
- Row-level security restricts every operation to `auth.uid() = user_id`.
- Deleting the auth user cascades to the vault row.
- `devices` is a directory of installations that have signed in. Its primary
  key is `(user_id, device_id)`, where `device_id` is a random id created on
  first launch and stored in `device.json`. It contains no secrets.
- Supabase/PostgREST has request size limits. The encrypted envelope is compact,
  but very large vaults (tens of thousands of items) should use a Storage bucket
  instead.

## Testing the setup

1. Run the app on Windows and create a vault.
2. Open **Settings → Account & sync**, create an account and sign in.
3. Confirm the row appears in **Table Editor → vaults**.
4. Install the APK on Android, choose **Sign in to sync an existing vault** on
   the setup screen, and sign in with the same account.
5. Enter the same master password. The vault downloads and unlocks.
