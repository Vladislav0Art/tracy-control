#!/usr/bin/env bash
set -u
cd /root/control

git config --global --add safe.directory '*'

claude -p "Read /root/control/TASK.md and execute the task defined in it. \
Work in /root/control. Make as much progress as you can." \
  2>&1 | tee /root/control/claude.log
status=${PIPESTATUS[0]}
echo "[entrypoint] Claude finished with exit ${status} - container staying alive for inspection." \
  | tee -a /root/control/claude.log

echo '[entrypoint] See logs at `/root/control/claude.log`'

exec sleep infinity
