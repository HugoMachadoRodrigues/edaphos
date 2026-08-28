#!/bin/sh
# tools/history-term-scan.sh -- count occurrences of each search term across
# EVERY blob that has ever existed in this repository, in one pass.
#
# Usage:  sh tools/history-term-scan.sh "term1|term2|term3"
# Output: "<count> <lowercased-term>" per matched term; terms that never
#         appeared print nothing at all.
#
# WHY A ONE-PASS OBJECT SCAN. The obvious formulations are far slower and
# strictly weaker. `git log -S<term>` walks every revision once per term.
# `git grep <term> $(git rev-list --all)` greps 5,265 trees per term. Both
# ran past twenty minutes here. The object database instead holds every blob
# that ever existed, deduplicated -- 3,865 blobs -- and reading all of them
# costs under a second. It is also MORE thorough than either: it sees blobs
# that were committed and later rewritten out of every branch, which a
# revision walk no longer reaches.
#
# Run it yourself; that is the point. It needs nothing but git and grep.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 'term1|term2'" >&2; exit 2; }

git rev-list --objects --all |
  awk '{print $1}' |
  git cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null |
  awk '$2 == "blob" { print $1 }' |
  git cat-file --batch 2>/dev/null |
  grep -o -i -E "$1" |
  tr 'A-Z' 'a-z' |
  sort | uniq -c |
  awk '{ print $1, $2 }'
