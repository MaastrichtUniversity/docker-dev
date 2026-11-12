#!/bin/bash
set -euo pipefail

# Clear the previous run's marker before the background import starts.
echo starting > /var/run/dh_import_state
/tmp/import.sh &
