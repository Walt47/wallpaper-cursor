#!/usr/bin/env sh
# session-logout.sh - make Noctalia's session-panel logout actually log out.
# Noctalia 5.0.1's built-in Mango logout path is a silent no-op (it logs
# "logout requested" and then does nothing), so this logging_out hook performs
# the session teardown itself. The hook fires immediately before the panel runs
# its (dead) logout sequence, for both the logout button and its number key.
#
# Primary: loginctl terminate-session on our own session -> back to ly greeter.
# Fallback: mmsg -q (quit Mango) when XDG_SESSION_ID is unexpectedly unset.
# Never fails the sequence: worst case it exits 0 and behavior is today's.
set -u
TAG="noctalia-hooks"

if [ -n "${XDG_SESSION_ID:-}" ]; then
  logger -t "$TAG" "session-logout: terminate-session $XDG_SESSION_ID (user: ${USER:-unknown})"
  loginctl terminate-session "$XDG_SESSION_ID" 2>/dev/null
  exit 0
fi

if command -v mmsg >/dev/null 2>&1; then
  logger -t "$TAG" "session-logout: no XDG_SESSION_ID, falling back to mmsg -q"
  mmsg -q 2>/dev/null
  exit 0
fi

logger -t "$TAG" "session-logout: no session id and no mmsg, nothing to do"
exit 0
