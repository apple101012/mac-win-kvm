# trust/

The installers write each machine's certificate fingerprint here:

- `server.sha256` is written by `windows\install.ps1`. Copy it to the Mac's `trust/`.
- `mac.sha256` is written by `mac/install.sh`. Copy it to the PC's `trust\`, then re-run `windows\install.ps1`.

These are fingerprints of public certificates, not secrets. They're still git-ignored, so your setup stays yours.
