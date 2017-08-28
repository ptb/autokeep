#!/bin/sh
# Initialize New Terminal

if test -z "${1}"; then
  osascript - $0 << EOF
    on run { this }
      tell app "Terminal" to do script "source " & quoted form of this & " 0"
    end run
EOF
fi

# Define Function =ask=

ask () {
  osascript << EOF 2> /dev/null
    tell app "System Events" to return text returned of (display dialog "${1}" with title "${1}" buttons {"Cancel", "${2}"} default answer "${3}")
EOF
}

# Define Function =run=

run () {
  osascript << EOF 2> /dev/null
    tell app "System Events" to return button returned of (display dialog "${1}" with title "${1}" buttons {"${2}", "${3}"} cancel button 1 default button 2 giving up after 5)
EOF
}

# Define Function =github_username=

github_username () {
  if git config github.user > /dev/null 2>&1; then
    a="$(git config github.user)"
  elif git config user.email > /dev/null 2>&1; then
    a=$(curl --location --silent \
      "https://api.github.com/search/users?q=$(git config user.email)" | \
      sed -n 's/^.*html_url.*: ".*\.com\/\(.*\)".*/\1/p')
  fi

  if test -n "${a}"; then
    open "https://github.com/${a}?tab=repositories"
    printf "${a}"
  else
    printf "$(ask 'GitHub username' 'OK' '')"
  fi
}

# Define Function =autokeep=

autokeep () {
  if test -n "${1}"; then
    git init --separate-git-dir="${1}"
    echo "gitdir: ${1}" > .git
    echo "${1}/" >> "$(git rev-parse --git-dir)/info/exclude"
  elif ! git rev-parse --git-dir > /dev/null 2>&1; then
    git init
  fi

  if ! git rev-parse --verify HEAD > /dev/null 2>&1; then
    git commit --allow-empty --allow-empty-message --message=
  fi

  autokeep_remote
  autokeep_push
  autokeep_gitignore
  autokeep_post_commit
  autokeep_launchagent
  autokeep_crypt
}

# Define Function =autokeep_remote=

autokeep_remote () {
  if ! git ls-remote --exit-code > /dev/null 2>&1; then
    a=$(github_username)
    b="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

    test -n "${a}" && \
      c="git@github.com:${a}/$(basename ${b}).git"

    d=$(ask "Remote Git Repository" "Add Remote" "${c}")

    test -n "${d}" && \
      git remote add origin "${d}"
  fi
}

# Define Function =autokeep_push=

autokeep_push () {
  if git ls-remote --exit-code > /dev/null 2>&1; then
    if git push --all --porcelain --set-upstream origin | grep -q "rejected"; then
      if ! run "Git push failed. Force push?" "Force Push" "Cancel"; then
        git push --all --force --set-upstream origin
      fi
    fi
  fi
}

# Define Function =autokeep_gitignore=

autokeep_gitignore () {
  cat << 'EOF' >> "$(git rev-parse --git-dir)/info/exclude"
# -*- mode: gitignore; -*-

**/Library/Caches/
**/Library/Saved\ Application\ State/

# Chrome downloads
*.crdownload

# Safari downloads
*.download/

# curl downloads
*.incomplete

# Firefox or Transmission downloads
*.part

*.plist.*
*.log
*.swp
*~
*~.skp
.\#*
\#*\#

.AppleDB
.AppleDesktop
.AppleDouble
.DS_Store
.DocumentRevisions-V100/
.LSOverride
.MobileBackups/
.Spotlight-V100/
.TemporaryItems/
.Trash/
.Trashes/
.VolumeIcon.icns
._*
.apdisk
.bundle
.checksums
.dropbox/
.dropbox.cache/
.fseventsd/
.sass-cache/
.svn/

node_modules/

/Network/*
/Previous Systems.localized/
/Volumes/*
/afs/*
/automount/*
/cores/*
/dev/*
/home/*
/net/*

/private/tmp/*
/private/var/folders/*
/private/var/run/*
/private/var/spool/postfix/*
/private/var/tmp/*
/private/var/vm/*

Icon

Network\ Trash\ Folder/
Temporary\ Items/

!.keep
EOF

  if test -n "${1}"; then
    echo "${1}/" >> "$(git rev-parse --git-dir)/info/exclude"
  fi
}

# Define Function =autokeep_post_commit=

autokeep_post_commit () {
  cat << 'EOF' > "$(git rev-parse --git-dir)/hooks/post-commit"
#!/bin/sh

if git ls-remote --exit-code > /dev/null 2>&1; then
  git push --all
  git push --tags
fi
EOF
  chmod +x "$(git rev-parse --git-dir)/hooks/post-commit"
}

# Define Function =autokeep_launchagent=

autokeep_launchagent () {
  if run "Automatically monitor for changes?" "Don't Monitor" "Monitor for Changes"; then
    a="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
    b="${HOME}/Library/LaunchAgents"
    c="com.github.ptb.autokeep.$(basename ${a})"
    d="${b}/${c}.plist"

    test -d "${b}" || \
      mkdir -m go= -p "${b}"

    test -f "${d}" && \
      launchctl unload "${d}" && \
      rm -f "${d}"

    printf "%s\t%s\t%s\n" \
      "Label" "-string" "${c}" \
      "ProgramArguments" "-array-add" "git" \
      "ProgramArguments" "-array-add" "commit" \
      "ProgramArguments" "-array-add" "--all" \
      "ProgramArguments" "-array-add" "--allow-empty-message" \
      "ProgramArguments" "-array-add" "--message=" \
      "RunAtLoad" "-bool" "true" \
      "WatchPaths" "-array-add" "${a}" \
      "WorkingDirectory" "-string" "${a}" \
    | while IFS="$(printf '\t')" read e f g; do
      defaults write "${d}" "${e}" $f "$g"
    done

    plutil -convert xml1 "${d}" && \
      chmod 600 "${d}" && \
      launchctl load "${d}"
  fi
}

# Define Function =autokeep_crypt=

autokeep_crypt () {
  test -z "$(git config alias.encrypt)" && \
    git config alias.encrypt '! a () { for c in "$@"; do if test -f "$c"; then printf "$(cd -P -- "$(dirname -- $c)" && pwd -P)/$(basename $c)" | sed -n "s| |[[:space:]]|gp;s|$(git rev-parse --show-toplevel)\(.*\)|\1 filter=crypt diff=crypt|p" >> "$(git rev-parse --git-dir)/info/attributes"; elif test -d "$c"; then find "$c" -type f -print0 | xargs -0 -I '{}' -L 1 printf "$(cd -P -- "$(dirname -- {})" && pwd -P)/$(basename {})\n" | sed -n "s| |[[:space:]]|g;s|$(git rev-parse --show-toplevel)\(.*\)|\1 filter=crypt diff=crypt|p" >> "$(git rev-parse --git-dir)/info/attributes"; fi; done; }; a'

  test -z "${CRYPTPASS}" && \
    CRYPTPASS="$(openssl rand -base64 48 | shasum -a 256 | base64 | sed 's/.\{4\}/&-/g' | head -c 19)"
  test -z "$(git config crypt.pass)" && \
    CRYPTPASS="$(ask 'Git encryption password' 'OK' ${CRYPTPASS})" && \
    git config crypt.pass "${CRYPTPASS}"

  test -z "${CRYPTSALT}" && \
    CRYPTSALT="$(openssl rand -hex 8)"
  test -z "$(git config crypt.salt)" && \
    CRYPTSALT="$(ask 'Git encryption salt' 'OK' ${CRYPTSALT})" && \
    git config crypt.salt "${CRYPTSALT}"

  test -z "$(git config crypt.cypher)" && \
    git config crypt.cypher "aes-256-ecb"

  test -z "$(git config diff.crypt)" && \
    git config diff.crypt 'C="$(git config crypt.cypher)" && P="$(git config crypt.pass)" && openssl enc -A -${C} -base64 -d -pass "pass:${P}" -in "${1}" 2> /dev/null || cat "${1}"'

  test -z "$(git config filter.crypt.clean)" && \
    git config filter.crypt.clean 'C="$(git config crypt.cypher)" && P="$(git config crypt.pass)" && S="$(git config crypt.salt)" && openssl enc -A -${C} -base64 -e -pass "pass:${P}" -S "${S}"'

  test -z "$(git config filter.crypt.smudge)" && \
    git config filter.crypt.smudge 'C="$(git config crypt.cypher)" && P="$(git config crypt.pass)" && openssl enc -A -${C} -base64 -d -pass "pass:${P}"'

  test -z "$(git config filter.crypt.required)" && \
    git config filter.crypt.required true

  test -z "$(git config hooks.cryptnames)" && \
    git config hooks.cryptnames true

  test -z "$(git config status.showUntrackedFiles)" && \
    git config status.showUntrackedFiles no

  test -z "$(git config merge.renormalize)" && \
    git config merge.renormalize true

  ci="$(git rev-parse --git-dir)/hooks/pre-commit"
  cat << EOF > "${ci}" && chmod +x "${ci}"
#!/usr/bin/env zsh

test "\$(git config --bool hooks.cryptnames)" != "true" && exit 0

WORKDIR="\$(git rev-parse --show-toplevel)"
CRYPTDIR="..."
GITDIR="\$(git rev-parse --git-dir)"
C="\$(git config crypt.cypher)"
P="\$(git config crypt.pass)"
S="\$(git config crypt.salt)"

(git rev-parse --verify HEAD 2> /dev/null && a=HEAD) || a=
git diff --cached --name-only --diff-filter=A -z \$a | while IFS= read -r -d '' b; do
  if [[ -f "\${b}" && -n \$(git check-attr -a -- "\${b}") ]]; then
    test -d "\${WORKDIR}/\${CRYPTDIR}" || mkdir -m go= -p "\${WORKDIR}/\${CRYPTDIR}"
    git reset "\${b}" && echo "\${b}" >> "\${GITDIR}/info/exclude"
    c=\$(openssl enc -A -\${C} -base64 -e -pass "pass:\${P}" -S "\${S}" <<< "\${b}" | tr -- "+/" "-_")
    test ! -f "\${WORKDIR}/\${CRYPTDIR}/\${c}" && \
      ln "\${b}" "\${WORKDIR}/\${CRYPTDIR}/\${c}" && \
      printf "%s\n" "/\${CRYPTDIR}/\${c} filter=crypt diff=crypt" >> "\${WORKDIR}/.gitattributes"
    git add "\${WORKDIR}/\${CRYPTDIR}/\${c}" "\${WORKDIR}/.gitattributes"
  fi
done
EOF

  co="$(git rev-parse --show-toplevel)/.post-checkout"
  cat << EOF > "${co}" && chmod +x "${co}"
#!/usr/bin/env zsh

setopt null_glob
WORKDIR="\${\$(git rev-parse --show-toplevel):-\$PWD}"
CRYPTDIR="..."
C="\${CYPHER:-\$(git config crypt.cypher)}"
P="\${CRYPTPASS:-\$(git config crypt.pass)}"

if test -d "\${WORKDIR}/\${CRYPTDIR}"; then
  FILES=(\${WORKDIR}/\${CRYPTDIR}/*)
  test -n "\${FILES}" && for b in \${FILES}; do
    c=\$(tr -- "-_" "+/" <<< "\$(basename \${b})" | openssl enc -A -\${C} -base64 -d -pass "pass:\${P}")
    d=\$(dirname "\${c}")
    test -d "\${d}" || mkdir -m go= -p "\${d}"
    if ! git rev-parse --git-dir > /dev/null 2>&1; then openssl enc -A -\${C} -base64 -d -pass "pass:\${P}" -in "\${b}" -out "\${c}"; fi
    test ! -f "\${c}" && ln "\${b}" "\${c}"
  done
fi
EOF
  ln "${co}" "$(git rev-parse --git-dir)/hooks/post-checkout"

  ia="$(git rev-parse --git-dir)/info/attributes"
  cat << EOF > "${ia}"
.git* !filter !diff
.gnupg/** filter=crypt diff=crypt
.ssh/** filter=crypt diff=crypt
EOF
}
