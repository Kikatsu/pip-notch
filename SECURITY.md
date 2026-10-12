# Security Policy

Pip sits between your AI coding agents and their permission prompts, so security reports are taken seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Instead, use GitHub's [private vulnerability reporting](https://github.com/Kikatsu/pip-notch/security/advisories/new).

Please include:

- What the issue is and what an attacker could do with it
- Steps to reproduce
- The Pip version (shown in Settings → General) and your macOS version

You should get a reply within a few days. Once a fix is released, you'll be credited in the release notes unless you'd rather not be.

## Scope

Things that are especially relevant:

- Ways for another local process to send fake approvals or events through Pip's Unix socket
- Ways a crafted hook payload could make Pip run commands, or approve a request the user didn't approve
- Hook installers corrupting or leaking the contents of agent config files

## Supported versions

Only the latest release is supported while Pip is in beta.
