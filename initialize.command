#!/bin/sh
CWD="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
HOOKS="${CWD}/.git/hooks"
LABEL="com.github.ptb.autokeep.$(basename ${CWD})"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

cd "${CWD}"

if [ -d "${CWD}/.git" ]; then
  while true; do
    read -n 1 -p "Re-Initialize Git Repository? " yn
    case $yn in
      [Yy]* ) rm -rf "${CWD}/.git"; break;;
      [Nn]* ) break;;
    esac
  done
  /bin/echo
fi

if [ ! -d "${CWD}/.git" ]; then
  git init
  git commit --allow-empty --allow-empty-message --message=
fi

if ! git ls-remote --exit-code github &> /dev/null; then
  wget \
    --output-document - \
    --quiet \
    "https://api.github.com/search/users?q=$(git config user.email)" \
    | sed -n "s/^.*html_url.*: \"\(.*\)\".*/\1?tab=repositories/p" \
    | xargs -L 1 open

  read -p "Remote Git Repository: " REPO_NAME

  if [[ ! -z "$REPO_NAME" ]]; then
    git remote add github "${REPO_NAME}"
    if git push --all --porcelain --set-upstream github | grep -q "rejected"; then
      /bin/echo
      while true; do
        read -n 1 -p "Force update? " yn
        case $yn in
          [Yy]* ) /bin/echo; /bin/echo; git push --all --force --set-upstream github; break;;
          [Nn]* ) /bin/echo; break;;
        esac
      done
    fi
  fi
fi

/bin/echo
while true; do
  read -n 1 -p "Create commit messages automatically? " yn
  case $yn in
    [Yy]* ) /bin/sh -c "cd '${HOOKS}' && ln -f '../../.prepare-commit-msg' 'prepare-commit-msg'"; break;;
    [Nn]* ) rm -f ".prepare-commit-msg" "${HOOKS}/prepare-commit-msg"; break;;
  esac
done
/bin/echo
/bin/echo

if [ -d "${HOOKS}" ] && [ ! -e "${HOOKS}/post-commit" ]; then
  /bin/sh -c "cd '${HOOKS}' && ln '../../.post-commit' 'post-commit'"
fi

launchctl unload "${PLIST}" &> /dev/null

cat > "${PLIST}" <<-EOF

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>git</string>
    <string>commit</string>
    <string>--all</string>
    <string>--allow-empty-message</string>
    <string>--gpg-sign</string>
    <string>--message=</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>WatchPaths</key>
  <array>
    <string>${CWD}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${CWD}</string>
</dict>
</plist>

EOF

plutil -convert xml1 "${PLIST}"
launchctl load "${PLIST}"

rm -f initialize.command autokeep.org readme.org
