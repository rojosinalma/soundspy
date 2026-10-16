# Security policy

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/rojosinalma/soundspy/security/advisories/new)
(Security tab → Report a vulnerability). Do not open a public issue. You will get an
acknowledgement within a week and a fix or a statement before any public disclosure.

## Supported versions

Only the latest release receives fixes. Upgrade `ghcr.io/rojosinalma/soundspy` to the newest
`vX.Y.Z` tag and the nodes to the matching firmware before reporting.

## What to keep in mind

1. The dashboard has no authentication of its own. Keep it on a trusted network or behind a reverse
   proxy that authenticates users; anyone who reaches it can rename nodes, change gain, put nodes to
   sleep and read the live audio.
2. Notification channel secrets (bot tokens, webhook URLs, SMTP passwords) are stored in
   `data/soundspy.db`. Protect that file like a credential store and redact it from bug reports.
3. The nodes' MQTT credentials and WiFi settings live in the boards' NVS and are entered through the
   setup portal, which is protected by the admin login. Use a broker that requires authentication.
4. The container runs as an unprivileged user, needs no capabilities and no Docker socket; mount
   only the `/app/data` volume.
