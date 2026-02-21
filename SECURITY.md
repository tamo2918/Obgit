# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest (`main`) | ✅ |

Obgit is distributed as source code. Security fixes are applied to the `main` branch and tagged as patch releases.

---

## Reporting a Vulnerability

**Please do not open a public GitHub Issue for security vulnerabilities.**

If you discover a security issue — especially one related to credential handling, SSH key storage, or authentication — please report it privately:

1. Go to the **[Security tab](../../security/advisories/new)** of this repository and open a private advisory, **or**
2. Email the maintainer directly (see the commit history for contact information).

Include:
- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof-of-concept (if available)
- Affected iOS versions and device types

We aim to respond within **72 hours** and to publish a fix within **14 days** of confirmation.

---

## Security Design

### Credential Storage

| Credential | Storage | Protection |
|---|---|---|
| Personal Access Token (PAT) | iOS Keychain (`kSecClassGenericPassword`) | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| SSH private key | iOS Keychain | Same as above |
| SSH passphrase | iOS Keychain | Same as above |
| Username | UserDefaults (JSON) | Non-sensitive; no secrets stored here |
| Repository URL | UserDefaults (JSON) | Non-sensitive |

- Credentials are **never** written to disk in plaintext.
- SSH private keys are loaded into memory for the duration of a Git operation and passed directly to libgit2 via `git_cred_ssh_key_memory_new()`. They are not written to the filesystem.

### Network

- All HTTPS communication relies on the OS-level TLS stack. SSL pinning is not implemented.
- SSH connections use the host's SSH server key. Host key verification is handled by libgit2.

### Known Limitations

- The app does not verify the scope of a provided PAT (e.g., whether it has `repo` access). An overly scoped PAT will function but is the user's responsibility to limit.
- No certificate pinning — connections are subject to standard iOS trust store evaluation.
- The app does not sandbox individual repository directories from each other beyond standard iOS app sandboxing.
