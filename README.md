# SecureID
a password manager, 2fa, and later Age Verification, coded from the get go to be built on security first.

Secure storage link between pc and phone for password storage, 2fa passkeys, and I later plan to add systems for ID Verification. This app is built on the highest security from the get-go. Current build is local only, though the program will be online when it's launched. 

ID will only be held for 7 days, then deleted and each user account will only have the checklist on the servers. Is @user over 16? Yes. Is @user over 18? Yes. Is @user over 21? Yes. Date of verification 09-11-2026 valid until 09-11-2031. Verified by CRA.
Password manager, and 2fa are to be stored on a separate server with hash level encryption, to prevent further breaks. If the ID part of SecureID gets hacked... All that is stored is the checklist, no IDs are stored beyond 7 days, as this is how long it may take for verification to officially occur from sources.

Still very much a work in progress, right now the working app only works locally on windows, and some android I plan to add further support later as I continue to build it. 

This is a side project for me. Vibe coding for both my own use, and my father's use. 

If you have any issues please contact me on my discord Bygone Era. At the bottom you will find the place called App Development. (https://discord.gg/4MFZWwvwpq) link

## Download

Prebuilt binaries are attached to the [latest release](https://github.com/Gyakudos/SecureID/releases/latest):

- **Windows** - `SecureID-Setup-1.2.5.exe` (per-user installer, Flutter runtime included, no admin rights needed)
- **Android** - `SecureID-1.2.5.apk`

## Building from source

See [docs/TECHNICAL.md](docs/TECHNICAL.md) for the architecture, security model and build steps.
