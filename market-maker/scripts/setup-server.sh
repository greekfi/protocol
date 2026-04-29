#!/usr/bin/env bash
# Deprecated. The first-time droplet setup now lives in
# market-maker/deploy/bootstrap.sh and runs *on* the droplet.
#
# To set up a new droplet, SSH in and run:
#   curl -sSL https://raw.githubusercontent.com/greekfi/protocol/main/market-maker/deploy/bootstrap.sh | bash
#
# See market-maker/DEPLOY.md for the full guide.

cat <<'EOF' >&2
This script is deprecated. Run the bootstrap *on the droplet* instead:

  ssh root@<droplet-ip>
  curl -sSL https://raw.githubusercontent.com/greekfi/protocol/main/market-maker/deploy/bootstrap.sh | bash

See market-maker/DEPLOY.md for the full guide.
EOF
exit 1
