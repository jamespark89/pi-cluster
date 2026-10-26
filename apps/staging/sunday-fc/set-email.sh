#!/usr/bin/env bash
# Sets the Gmail account Sunday FC sends email from, without the password
# showing on screen or in shell history.
#   bash set-email.sh [gmail address]
set -euo pipefail

email="${1:-mel.jamespark@gmail.com}"
read -r -s -p "Gmail app password for $email (16 letters): " pw
echo
pw="${pw// /}" # Google shows it in groups of four; spaces aren't part of it.
if [[ ! "$pw" =~ ^[a-z]{16}$ ]]; then
  echo "That doesn't look like an app password (16 letters). Nothing changed." >&2
  exit 1
fi

kubectl -n sunday-fc patch secret sunday-fc-env --type merge -p "$(
  printf '{"stringData":{"EMAIL_SERVER":"smtps://%s:%s@smtp.gmail.com:465","EMAIL_FROM":"Sunday FC <%s>"}}' \
    "${email/@/%40}" "$pw" "$email"
)" >/dev/null
unset pw
echo "Email settings saved for $email."
kubectl -n sunday-fc rollout restart deployment/sunday-fc
kubectl -n sunday-fc rollout status deployment/sunday-fc --timeout=120s
