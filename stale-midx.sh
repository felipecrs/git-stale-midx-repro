#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${REPRO_DATA_DIR:-$PWD/.repro}"
MIDX_DIR="${REPRO_MIDX_DATA_DIR:-$DATA_DIR/midx}"
BLOB_KB="${BLOB_KB:-256}"

export GIT_AUTHOR_NAME=repro
export GIT_AUTHOR_EMAIL=repro@example.com
export GIT_COMMITTER_NAME=repro
export GIT_COMMITTER_EMAIL=repro@example.com

REMOTE="$MIDX_DIR/remote.git"
MIRROR="$MIDX_DIR/mirror.git"
REMOTE_URL="file://$MIDX_DIR/remote.git"

step() { printf '\n=== %s ===\n' "$*"; }
clean_staging() { rm -f "$MIRROR"/objects/pack/.tmp-*; }

rm -rf "$MIDX_DIR"
mkdir -p "$MIDX_DIR"

step "build remote history: two branches and two large files"
git init -q --bare "$REMOTE"
git -C "$REMOTE" config gc.auto 0
git -C "$REMOTE" symbolic-ref HEAD refs/heads/development

tmp_index="$MIDX_DIR/tmp-index"
trap 'rm -f "$tmp_index" "$MIDX_DIR/base.tmp"' EXIT
export GIT_INDEX_FILE="$tmp_index"
git -C "$REMOTE" read-tree --empty

head -c $((BLOB_KB * 1024)) /dev/urandom > "$MIDX_DIR/base.tmp"
base_blob=$(git -C "$REMOTE" hash-object -w "$MIDX_DIR/base.tmp")
git -C "$REMOTE" update-index --add --cacheinfo "100644,$base_blob,base.bin"
head -c $((BLOB_KB * 1024)) /dev/urandom > "$MIDX_DIR/base.tmp"
other_blob=$(git -C "$REMOTE" hash-object -w "$MIDX_DIR/base.tmp")
git -C "$REMOTE" update-index --add --cacheinfo "100644,$other_blob,other.bin"
tree=$(git -C "$REMOTE" write-tree)
first_commit=$(git -C "$REMOTE" commit-tree "$tree" -m "first commit with base.bin and other.bin")
git -C "$REMOTE" update-ref refs/heads/development "$first_commit"
git -C "$REMOTE" update-ref refs/heads/release "$first_commit"
unset GIT_INDEX_FILE

step "clone the mirror: one initial pack holds the whole history"
git clone -q --bare "$REMOTE" "$MIRROR"
git -C "$MIRROR" config gc.auto 0
git -C "$MIRROR" config gc.autoDetach false
git -C "$MIRROR" config maintenance.auto false
git -C "$MIRROR" config fetch.unpackLimit 1
git -C "$MIRROR" config transfer.unpackLimit 1
git -C "$MIRROR" repack -q -a -d --no-write-midx --no-write-bitmap-index
rm -f "$MIRROR"/objects/pack/multi-pack-index*
clean_staging
initial_pack=$(ls "$MIRROR"/objects/pack/pack-*.idx | sed 's/.*\///;s/\.idx$//')
echo "initial pack: $initial_pack"

step "a gc consolidation copies the already fetched history into a second pack"
sleep 1
git -C "$MIRROR" rev-list --objects refs/heads/release | grep -v "^$base_blob" | awk '{print $1}' | git -C "$MIRROR" pack-objects --quiet "$MIRROR/objects/pack/pack" >/dev/null
consolidated_pack=""
for name in $(ls "$MIRROR"/objects/pack/pack-*.idx | sed 's/.*\///;s/\.idx$//'); do
  [ "$name" = "$initial_pack" ] || consolidated_pack="$name"
done
echo "consolidated pack: $consolidated_pack (every object of the first commit except one blob, newer than $initial_pack)"

step "a normal fetch brings the next commit in a fresh pack"
git -C "$REMOTE" cat-file blob "$base_blob" > "$MIDX_DIR/base.tmp"
printf 'round 2 change\n' >> "$MIDX_DIR/base.tmp"
new_blob=$(git -C "$REMOTE" hash-object -w "$MIDX_DIR/base.tmp")
GIT_INDEX_FILE="$tmp_index" git -C "$REMOTE" read-tree refs/heads/development^{tree}
GIT_INDEX_FILE="$tmp_index" git -C "$REMOTE" update-index --cacheinfo "100644,$new_blob,base.bin"
tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$REMOTE" write-tree)
parent=$(git -C "$REMOTE" rev-parse refs/heads/development)
commit=$(git -C "$REMOTE" commit-tree "$tree" -p "$parent" -m "round 2 touches base.bin")
git -C "$REMOTE" update-ref refs/heads/development "$commit"
git -C "$MIRROR" fetch -q "$REMOTE_URL" "+refs/heads/development:refs/heads/development"
rm -f "$MIDX_DIR/base.tmp"
fetch_pack=""
for name in $(ls "$MIRROR"/objects/pack/pack-*.idx | sed 's/.*\///;s/\.idx$//'); do
  case "$name" in "$initial_pack"|"$consolidated_pack") ;; *) fetch_pack="$name" ;; esac
done
clean_staging
echo "fetch pack: $fetch_pack (development tip lives only here)"

step "native auto-gc writes a multi-pack-index over the current packs, its last update"
git -C "$MIRROR" multi-pack-index write
echo "objects map to their newest holder: first commit objects to $consolidated_pack, round 2 objects to $fetch_pack"

step "the concurrent gc deletes the consolidated pack the snapshot still maps old objects to"
rm -f "$MIRROR/objects/pack/$consolidated_pack.pack"
echo "deleted $consolidated_pack.pack, its idx remains, its objects still exist in $initial_pack"

step "symptom 1: the release branch looks like a dangling ref, its commit appears missing"
git -C "$MIRROR" rev-parse refs/heads/release
set +e
git -C "$MIRROR" cat-file -t "$(git -C "$MIRROR" rev-parse refs/heads/release)" 2>&1
catfile_rc=$?
set -e
echo "cat-file exit=$catfile_rc (the branch tip looks like a dangling ref)"
[ "$catfile_rc" -ne 0 ] || { echo "SYMPTOM 1 DID NOT REPRODUCE"; exit 1; }

step "symptom 2: fsck reports failed pack loads and unreadable entries"
set +e
git -C "$MIRROR" fsck --connectivity-only --no-dangling 2>&1 | head -8
set -e

step "symptom 3: a change collection fails with the incident error"
git -C "$REMOTE" cat-file blob "$other_blob" > "$MIDX_DIR/base.tmp"
printf 'the incident push %s\n' "$(date +%s)" >> "$MIDX_DIR/base.tmp"
new_blob=$(git -C "$REMOTE" hash-object -w "$MIDX_DIR/base.tmp")
GIT_INDEX_FILE="$tmp_index" git -C "$REMOTE" read-tree refs/heads/development^{tree}
GIT_INDEX_FILE="$tmp_index" git -C "$REMOTE" update-index --cacheinfo "100644,$new_blob,other.bin"
tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$REMOTE" write-tree)
parent=$(git -C "$REMOTE" rev-parse refs/heads/development)
commit=$(git -C "$REMOTE" commit-tree "$tree" -p "$parent" -m "incident push touching other.bin")
git -C "$REMOTE" update-ref refs/heads/development "$commit"
rm -f "$MIDX_DIR/base.tmp"

set +e
fetch_out="$MIDX_DIR/fetch.out"
git -C "$MIRROR" fetch --progress "$REMOTE_URL" "+refs/heads/development:refs/heads/development" 2>"$fetch_out"
fetch_rc=$?
set -e
grep -E 'Resolving deltas|unresolved deltas|invalid index-pack' "$fetch_out" | tail -3
echo "fetch exit=$fetch_rc"
[ "$fetch_rc" -ne 0 ] || { echo "SYMPTOM 3 DID NOT REPRODUCE"; exit 1; }
corpse=$(find "$MIRROR/objects/pack" -name 'tmp_pack_*' 2>/dev/null | wc -l | tr -d ' ')
echo "tmp_pack corpses left behind: $corpse (a busy mirror accumulates hundreds because failed fetches retry for hours)"
rm -f "$fetch_out"

step "the fix that worked in production: move the stale multi-pack-index aside"
mv "$MIRROR/objects/pack/multi-pack-index" "$MIRROR/objects/pack/multi-pack-index.stale-demo"
rm -f "$MIRROR"/objects/pack/*.rev
rm -f "$MIRROR/objects/pack/$consolidated_pack.idx"
git -C "$MIRROR" cat-file -t "$(git -C "$MIRROR" rev-parse refs/heads/release)" >/dev/null
echo "the release tip is readable again, no re-clone needed"

set +e
heal_out="$MIDX_DIR/heal.out"
git -C "$MIRROR" fetch --progress "$REMOTE_URL" "+refs/heads/development:refs/heads/development" 2>"$heal_out"
heal_rc=$?
set -e
grep -E 'unresolved|invalid|->' "$heal_out" | tail -2 || true
echo "pending collection fetch exit=$heal_rc"
rm -f "$heal_out"
git -C "$MIRROR" fsck --connectivity-only --no-dangling
echo "fsck exit=$?"

step "rebuild a fresh multi-pack-index from the packs that exist"
clean_staging
git -C "$MIRROR" multi-pack-index write
git -C "$MIRROR" fetch -q "$REMOTE_URL" "+refs/heads/development:refs/heads/development"
git -C "$MIRROR" fsck --connectivity-only --no-dangling && echo "mirror healthy with a fresh index"