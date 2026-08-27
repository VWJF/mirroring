#!/usr/bin/env bash
# Always-on notice: mirroring copies git history onto another host.
set -euo pipefail

cat <<'EOF'
WARNING: This Action copies git history (commits, trees, and the triggering ref)
from this GitHub repository to another Git server.

Once that copy exists, it is no longer covered only by this server's access
control, retention, residency, or terms. Private vs public, self-hosted vs
cloud, and GitLab vs GitHub (including GitHub Enterprise) can all differ.
Mirroring is one-way per hop, but the data has still left the original space.

You (the operator) must decide that the destination is allowed to hold this
data, and must exercise due care (visibility, secrets in git history, policy,
and law). The authors of this Action are not responsible or liable for how it
is used or for data that leaves the source as a result.

See README.md (Warning and disclaimer) and FAQ.md.
EOF

# Annotation appears on the job in the Actions UI (one line; no newlines).
echo "::warning title=Git data leaves this server::This Action copies commits to another Git host. Access control, privacy, and law on the destination may differ from the source. You are responsible for that copy. The Action authors are not liable. See VWJF/mirroring README and FAQ."
