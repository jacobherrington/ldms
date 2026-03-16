# Security Policy

## Supported versions

LDMS is currently pre-1.0. Security fixes are applied to the latest minor release.

## Reporting a vulnerability

Do not open public issues for vulnerabilities.

Instead, report privately with:
- impact summary
- reproduction steps
- affected version/commit
- suggested mitigation (if known)

Maintainers will acknowledge reports within 3 business days.

## Security boundaries

LDMS is designed for local-first use:
- Memory is stored in local SQLite by default.
- Embeddings are generated through local Ollama by default.
- UI binds to localhost by default unless explicitly overridden.

LDMS should not be treated as a secret vault. Avoid storing credentials, tokens, or private keys.
