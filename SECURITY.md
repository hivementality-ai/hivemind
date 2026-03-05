# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Hivemind, **please report it responsibly**. Do not open a public issue.

### How to report

Email **security@hivementality.ai** with:

- A description of the vulnerability
- Steps to reproduce (or a proof-of-concept)
- The affected version(s) or commit hash
- Your assessment of severity and impact

### What to expect

| Step | Timeline |
|------|----------|
| Acknowledgment | Within 48 hours |
| Initial assessment | Within 5 business days |
| Fix or mitigation | Depends on severity (see below) |
| Public disclosure | Coordinated with reporter |

### Severity response times

| Severity | Target fix time |
|----------|----------------|
| **Critical** (RCE, auth bypass, data leak) | 48 hours |
| **High** (privilege escalation, injection) | 7 days |
| **Medium** (information disclosure, CSRF) | 30 days |
| **Low** (minor, defense-in-depth) | Next release |

### Scope

The following are in scope:

- The Hivemind application (Rails, Sidekiq, connectors)
- Docker configuration and container isolation
- Authentication and authorization (Devise, API tokens)
- Encrypted vault and secrets management
- Webhook signature verification
- Agent workspace isolation
- Skill import security scanning

The following are **out of scope**:

- Third-party dependencies (report upstream, but let us know)
- Social engineering attacks
- Denial of service via rate limiting exhaustion (we use Rack::Attack)
- Vulnerabilities in LLM providers (Anthropic, OpenAI, Ollama)

### Safe harbor

We will not pursue legal action against security researchers who:

- Act in good faith and follow this policy
- Avoid accessing or modifying other users' data
- Do not disrupt production services
- Report findings privately before any public disclosure

### Recognition

We're happy to credit researchers in release notes (with permission). We do not currently offer a paid bounty program.

## Security architecture

For an overview of Hivemind's security layers, see the [Security section](README.md#security) in the README.

## Supported versions

We provide security fixes for the **latest stable release** only. Running `hivemind update` will pull the latest patched version.
