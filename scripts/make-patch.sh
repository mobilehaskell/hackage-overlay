#!/bin/sh
set -e

die () {
    echo "ERROR: $1" >& 2
    exit 1
}

OVL_OWNER=mobilehaskell
OVL_REPO=hackage-overlay
OVL_NAME=mobilehaskell


usage () {
    echo "Usage:
  ${0##*/} <name>-<version>

  Will roughly perform the following operations:
  $ git fetch \$hvr/head.hackage
  $ git checkout -b <name>-<version> \$hvr/head.hackage/master
  $ mv <name>-<version> <name>-<version>-patched
  $ cabal unpack --pristine <name>-<version>
  $ diff -ru <name>-<version> <name>-<version>-patched > \$head.hackage/patches/<name>-<version>.patch
  $ mv -f <name>-<version>-patched <name>-<version>
  $ git add patches/<name>-<version>.patch
  $ git commit -m \"Adds <name>-<version>.patch\"
  $ git push

  All that's left is opening the PR against \$hvr/head.hackage"
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

if [ ! -f "$HOME/.hackage.${OVL_NAME}-overlay" ]; then
    die "$HOME/.hackage.${OVL_NAME}-overlay file not found."
fi
source "$HOME/.hackage.${OVL_NAME}-overlay"

if [ -z "$OVL_CLONE_PATH" ]; then
    die "${OVL_NAME} local repository ('\$OVL_CLONE_PATH') not set; please edit $HOME/.hackage.${OVL_NAME}-overlay."
fi
if [ ! -d "$OVL_CLONE_PATH" ]; then
    die "${OVL_NAME} local repository ('\$OVL_CLONE_PATH') doesn't seem to exist; please edit $HOME/.hackage.${OVL_NAME}-overlay."
fi
if [ ! -d "$OVL_CLONE_PATH/.git" ]; then
    die "head.hackage local repository ('\$OVL_CLONE_PATH') doesn't seem to be a git repository; please edit $HOME/.hackage.${OVL_NAME}-overlay."
fi

UPSTREAM_FETCH_NAME=$(git -C "$OVL_CLONE_PATH" remote -v |grep "${OVL_OWNER}/${OVL_REPO}.*fetch"|awk -F\  '{ print $1 }')

if [ -z "$UPSTREAM_FETCH_NAME" ] ; then
    echo "no ${OVL_OWNER}/${OVL_REPO} remote found. Adding..."
    git -C "$OVL_CLONE_PATH" remote add "${OVL_NAME}" "https://github.com/${OVL_OWNER}/${OVL_REPO}.git"
    UPSTREAM_FETCH_NAME="${OVL_NAME}"
fi

git -C "$OVL_CLONE_PATH" fetch "$UPSTREAM_FETCH_NAME"
git -C "$OVL_CLONE_PATH" checkout -b "$1" "$UPSTREAM_FETCH_NAME/master"

if [ ! -d "$OVL_CLONE_PATH/patches" ]; then
    die "$OVL_CLONE_PATH/patches does not exist!"
fi

if [ -f "$OVL_CLONE_PATH/patches/$1.patch" ]; then
    die "$OVL_CLONE_PATH/patches/$1.patch already exists!"
fi

echo "creating patch..."
mv "$1" "$1-patched"
cabal unpack --pristine "$1"

# diff returns 0 for no changes; 1 for some changes; and 2 for trouble
set +e
diff -ru "$1" "$1-patched" > "$OVL_CLONE_PATH/patches/$1.patch"
exit_status=$?
set -e
if [ $exit_status -eq 1 ]; then
    echo "creating commit..."
    git -C "$OVL_CLONE_PATH" add "patches/$1.patch"
    git -C "$OVL_CLONE_PATH" commit -m "Adds $1.patch"
    git -C "$OVL_CLONE_PATH" push origin

    echo "Please go to https://github.com/${OVL_OWNER}/${OVL_REPO}"
else
    echo "failed to create patch... exit: $?"
    "$OVL_CLONE_PATH/patches/$1.patch"
    git -C "$OVL_CLONE_PATH" checkout master
    git -C "$OVL_CLONE_PATH" branch -d "$1"
fi
echo "moving $1-patched to $1"
rm -fR "$1"
mv "$1-patched" "$1"
