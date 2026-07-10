#!/usr/bin/env bash
# build-link-graph.sh <wiki_dir> — 볼트 wiki/를 1회 패스로 읽어 링크 그래프를 구축하고
# 결정론적 파생 사실을 출력한다. 하네스 스펙 §4-6 (wiki-lint 전용 공용 스크립트).
# 본문 [[link]] + frontmatter relationships target을 한 그래프로 통합.
# 출력(탭 구분, 정렬됨):
#   ORPHAN     <page>                 인바운드 0 (항목 1)
#   BROKEN     <src> <target_raw>     본문 [[링크]] 대상 부재 (항목 2·9)
#   REL_BROKEN <src> <target_raw>     relationships target 부재 (항목 12)
#   REL_SELF   <src> <target_raw>     relationships target 자기참조 (항목 12)
#   SUMMARY nodes=N orphans=N broken=N rel_broken=N rel_self=N
# index.md·log.md·hot.md는 스캔·인바운드 계수에서 제외 (§4-6).
set -u

[ $# -ge 1 ] || { echo "usage: build-link-graph.sh <wiki_dir>" >&2; exit 2; }
WIKI="$1"
[ -d "$WIKI" ] || { echo "wiki 디렉토리 없음: $WIKI" >&2; exit 2; }

python3 - "$WIKI" <<'PY'
import sys, os, re

wiki = os.path.abspath(sys.argv[1])
EXCLUDE = {"index.md", "log.md", "hot.md"}      # wiki 루트 특수 파일

# ── 페이지 수집 (relpath, .md) ──────────────────────────────
pages = []
for root, _, files in os.walk(wiki):
    for fn in files:
        if not fn.endswith(".md"):
            continue
        rel = os.path.relpath(os.path.join(root, fn), wiki).replace("\\", "/")
        if rel in EXCLUDE:                       # 루트 index/log/hot만 제외
            continue
        pages.append(rel)
pages.sort()

relset = set(p[:-3] for p in pages)              # ".md" 제거한 상대경로 집합
bybase = {}
for p in pages:
    bybase.setdefault(os.path.basename(p)[:-3], []).append(p[:-3])

def resolve(target):
    """[[target]] → 해석된 페이지 relpath(.md 제거) 또는 None."""
    t = target.split("|")[0].split("#")[0].strip()
    if t.startswith("wiki/"):
        t = t[5:]
    if t.endswith(".md"):
        t = t[:-3]
    if t in relset:
        return t
    base = t.split("/")[-1]
    if base in bybase:
        return bybase[base][0]
    return None

WIKILINK = re.compile(r'\[\[([^\]]+)\]\]')

def split_frontmatter(text):
    m = re.match(r'^---\n(.*?)\n---\n?(.*)$', text, re.S)
    if m:
        return m.group(1), m.group(2)
    return "", text

# relationships 블록의 target: "[[...]]" 만 추출
def rel_targets(fm):
    out = []
    in_rel = False
    for line in fm.split("\n"):
        stripped = line.strip()
        if re.match(r'^relationships\s*:', line):
            in_rel = True
            continue
        # 다음 최상위 키(들여쓰기 0, 콜론 포함)를 만나면 블록 종료
        if in_rel and line and not line[0].isspace() and ":" in line:
            in_rel = False
        if in_rel and "target" in stripped:
            mm = WIKILINK.search(stripped)
            if mm:
                out.append(mm.group(1))
    return out

inbound = {p[:-3]: 0 for p in pages}
broken, rel_broken, rel_self = [], [], []

for p in pages:
    src = p[:-3]
    text = open(os.path.join(wiki, p), encoding="utf-8").read()
    fm, body = split_frontmatter(text)

    # 본문 [[링크]]
    for raw in WIKILINK.findall(body):
        r = resolve(raw)
        if r is None:
            broken.append((p, raw))
        elif r != src:                           # 자기참조는 인바운드로 세지 않음
            inbound[r] = inbound.get(r, 0) + 1

    # frontmatter relationships target
    for raw in rel_targets(fm):
        r = resolve(raw)
        if r is None:
            rel_broken.append((p, raw))
        elif r == src:
            # 자기참조: relationship 오류로 보고하되 인바운드로 세지 않는다.
            # (자기 자신을 세면 진짜 고아가 ORPHAN 판정에서 누락됨)
            rel_self.append((p, raw))
        else:
            inbound[r] = inbound.get(r, 0) + 1

orphans = sorted(p for p in pages if inbound.get(p[:-3], 0) == 0)

out = []
for p in orphans:
    out.append("ORPHAN\t%s" % p)
for src, raw in sorted(broken):
    out.append("BROKEN\t%s\t%s" % (src, raw))
for src, raw in sorted(rel_broken):
    out.append("REL_BROKEN\t%s\t%s" % (src, raw))
for src, raw in sorted(rel_self):
    out.append("REL_SELF\t%s\t%s" % (src, raw))
out.append("SUMMARY nodes=%d orphans=%d broken=%d rel_broken=%d rel_self=%d" %
           (len(pages), len(orphans), len(broken), len(rel_broken), len(rel_self)))
print("\n".join(out))
PY
