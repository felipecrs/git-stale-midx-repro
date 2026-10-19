# Stale multi-pack-index reproduction for git 2.54

A minimal, deterministic reproduction of a bare-repository corruption state where the
multi-pack-index references pack files that no longer exist on disk. Every git command that
trusts the index then fails for the objects it maps to the dead packs, even though every object
still exists in other packs on disk. Reproduced and verified on git 2.54.0.

## The failure

A busy bare mirror (the kind a CI server keeps for change detection) ends up in a state where:

- Reading a branch tip fails with `fatal: git cat-file: could not get object info`, which looks
  exactly like a dangling ref. The ref is fine; only the index is stale. This is easy to
  misdiagnose as ref corruption.
- `git fsck` reports `refs/heads/...: invalid sha1 pointer`, `failed to load pack in position N`
  and `failed to load pack entry for oid[...]` for objects that still exist in other packs.
- Every `git fetch` fails with `fatal: fetch-pack: invalid index-pack output`, because the thin
  pack received from the server has delta bases the client cannot resolve: the bases are mapped
  to the dead packs. Each failed fetch leaves a `tmp_pack_*` corpse in the pack directory.

For any object the multi-pack-index maps to a listed pack, git trusts the index exclusively and
never falls back to searching other packs that also hold a copy. That is why a stale index breaks
objects whose live copies are still on disk, and why the damage persists until the index is
rewritten.

The recovery is to move the stale index aside. Without it git searches pack by pack again,
finds the live copies, and the next fetch re-downloads whatever was missing. No re-clone needed.

## How the index goes stale

On git 2.54, a fetch that keeps its incoming pack triggers automatic maintenance, which runs a
**detached background gc**: it repacks everything into a new pack, writes or refreshes the
multi-pack-index, and then deletes the packs it consolidated. This happens even with `gc.auto=0`
in the config; the maintenance path does not respect it (`maintenance.auto=false` or
`gc.autoDetach=false` do change the behaviour). Because the gc is detached, it can still be
running after the fetch command has already returned, so it races anything else touching the
pack directory, including another gc, an external cleanup, or a monitoring process that removes
packs. When deletions and index writes interleave, the index on disk references packs that are
already gone, and no later incremental index write revalidates those entries.

Verified on git 2.54.0: fetch-with-kept-pack, `gc.auto=0`, no other command running, the pack
set collapses to one consolidated pack plus a fresh multi-pack-index within a second of the
fetch returning.

## The reproduction

`stale-midx.sh` builds a small bare mirror and walks it through the exact state, with the
background maintenance disabled so the layout stays deterministic:

1. A remote with two branches and two 256KB files; the mirror is cloned from it, giving one
   initial pack holding the first commit.
2. A gc-style consolidation copies the first commit's objects (except one blob) into a second,
   newer pack.
3. A normal fetch brings the second commit in a third pack. The thin fetch also carries a copy
   of the base blob, so every object now lives in at least one pack that stays alive.
4. A multi-pack-index is written over the current pack set: the index maps each object to its
   newest holder, so first-commit objects point at the consolidated pack and second-commit
   objects at the fetch pack. This is the index's last update.
5. The concurrent gc deletes the consolidated pack while the index still maps the old objects to
   it. Its objects still exist in the initial pack.
6. The three symptoms above, one by one. The script fails loudly if a symptom does not reproduce.
7. The recovery: move the index aside, show the branch tip is readable again, the pending
   fetch succeeds, fsck is clean, and a fresh index is rebuilt.

## Running it

Needs git 2.54 and bash. The easiest way is Docker:

```bash
docker run --rm \
  -v "$PWD/stale-midx.sh":/scripts/stale-midx.sh \
  -v "$PWD/.repro":/data \
  -e REPRO_MIDX_DATA_DIR=/data/run \
  --entrypoint sh alpine/git:2.54.0 \
  -c 'apk add -q bash >/dev/null 2>&1; bash /scripts/stale-midx.sh'
```

Or on any machine with git 2.54:

```bash
./stale-midx.sh
```

The script writes its data to `$REPRO_MIDX_DATA_DIR`, defaulting to `$REPRO_DATA_DIR/midx`
(default `$PWD/.repro`). It removes and recreates that directory on every run.

Determinism: the index maps an object to its newest holding pack using second-granularity file
timestamps, so packs created within the same wall-clock second tie and the mapping becomes
unpredictable (see the quirks list below). The script sleeps before the consolidation step to
keep the pack timestamps in distinct seconds, which makes the construction deterministic: six
consecutive runs with different random blob content each reproduced all three symptoms and the
full recovery.

Expected result, three symptoms then full recovery:

```
=== symptom 1: the release branch looks like a dangling ref, its commit appears missing ===
fatal: git cat-file: could not get object info
cat-file exit=128 ...

=== symptom 2: fsck reports failed pack loads and unreadable entries ===
error: refs/heads/release: invalid sha1 pointer ...
error: Could not read ...
failed to load pack in position 1
failed to load pack entry for oid[...] ...

=== symptom 3: a change collection fails with the incident error ===
Resolving deltas: 0% (0/1) ...
fatal: fetch-pack: invalid index-pack output
fetch exit=128
tmp_pack corpses left behind: 1 ...

=== the fix that worked in production: move the stale multi-pack-index aside ===
the release tip is readable again, no re-clone needed
pending collection fetch exit=0
fsck exit=0
mirror healthy with a fresh index
```

Two consecutive runs with different random blob content reproduce all three symptoms and the
full recovery, so the construction does not depend on luck.

## Related git 2.54 issues observed while building this

All confirmed on `alpine/git:2.54.0`:

- A fetch that keeps its pack triggers a detached maintenance gc that consolidates packs and
  writes a multi-pack-index even when `gc.auto=0` is set.
- `index-pack --fix-thin` leaves its staging files behind after finalizing a pack: hidden
  `.tmp-<pid>-pack-<hash>.{pack,idx,rev}` dotfiles accumulate on every fetch.
- `git multi-pack-index write` globs `*.idx`, which matches those hidden staging files, so the
  index can list staged pack names that never exist as real packs.
- A failed fetch leaves a `tmp_pack_*` corpse in the pack directory.
- `git pack-objects` silently writes nothing when its output pack hash equals a pack that
  already exists, which makes "consolidate into a new pack" a no-op when the content would be
  identical.
- The multi-pack-index maps each object to its newest holding pack by file timestamp, at
  second granularity. Packs created within the same wall-clock second tie, and which pack wins
  the tie is not predictable from the outside, so two mirrors built in the same second can get
  different mappings.

## Tested with

- git 2.54.0 (`alpine/git:2.54.0` Docker image)
- bash on Alpine Linux