#!/usr/bin/env bash
# validate-frontmatter.sh <file> — frontmatter 기계 검증. 하네스 스펙 §3-3.
# 경로/category로 문서 클래스(①페이지 ②라이프사이클 ③원장) 판정 후 클래스별 규칙 적용.
# 클래스③(원장)은 검증 면제. 통과=exit 0, 위반=exit 1 + stderr에 항목별 메시지.
# 의미적 품질(요약 정확성 등)은 검증하지 않는다 — wiki-lint의 몫.
set -u

[ $# -ge 1 ] || { echo "usage: validate-frontmatter.sh <file>" >&2; exit 2; }
FILE="$1"
[ -f "$FILE" ] || { echo "파일 없음: $FILE" >&2; exit 2; }

python3 - "$FILE" <<'PY'
import sys, os, re

path = sys.argv[1]
base = os.path.basename(path)
parts = path.replace("\\", "/").split("/")
errors = []

# ── 클래스 판정 ──────────────────────────────────────────────
LEDGER = {"index.md", "log.md", "hot.md", "decisions.md", "backlog.md"}
if base in LEDGER:
    sys.exit(0)                      # 클래스③ 원장 — 검증 면제
if "changes" in parts:
    cls = "changes"                  # 클래스② changes
elif "troubleshooting" in parts:
    cls = "troubleshooting"          # 클래스② troubleshooting
else:
    cls = "page"                     # 클래스① 풀세트

# ── frontmatter 추출 ────────────────────────────────────────
text = open(path, encoding="utf-8").read()
m = re.match(r'^---\n(.*?)\n---', text, re.S)
if not m:
    print("frontmatter 블록(--- ... ---)이 없습니다", file=sys.stderr)
    sys.exit(1)
fm = m.group(1)

# ── 최소 YAML-부분집합 파서 ──────────────────────────────────
def strip_scalar(v):
    v = v.strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    return v

def indent(s):
    return len(s) - len(s.lstrip(" "))

def parse_block(block):
    items = [l for l in block if l.strip() and not l.lstrip().startswith("#")]
    if not items:
        return None
    if items[0].lstrip().startswith("- "):
        result, cur = [], None
        for l in items:
            s = l.strip()
            if s.startswith("- "):
                rest = s[2:].strip()
                if ":" in rest:
                    k, _, v = rest.partition(":")
                    cur = {k.strip(): strip_scalar(v)}
                    result.append(cur)
                else:
                    result.append(strip_scalar(rest)); cur = None
            elif ":" in s and isinstance(cur, dict):
                k, _, v = s.partition(":")
                cur[k.strip()] = strip_scalar(v)
        return result
    d = {}
    for l in items:
        s = l.strip()
        if ":" in s:
            k, _, v = s.partition(":")
            d[k.strip()] = strip_scalar(v)
    return d

def parse_fm(fm):
    data = {}
    lines = fm.split("\n")
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1; continue
        if indent(line) == 0 and ":" in line:
            key, _, rest = line.partition(":")
            key, rest = key.strip(), rest.strip()
            if rest == "":
                block, j = [], i + 1
                while j < n and (not lines[j].strip() or indent(lines[j]) > 0):
                    block.append(lines[j]); j += 1
                data[key] = parse_block(block); i = j
            elif rest.startswith("[") and rest.endswith("]"):
                inner = rest[1:-1].strip()
                data[key] = [strip_scalar(x) for x in inner.split(",")] if inner else []
                i += 1
            else:
                data[key] = strip_scalar(rest); i += 1
        else:
            i += 1
    return data

d = parse_fm(fm)

# ── 클래스별 필수 키 + status enum ──────────────────────────
REQUIRED = {
    "page":           ["title","category","tags","sources","created","updated","summary","status","base_confidence"],
    "changes":        ["title","category","project","targets","status","created","status_changed","summary","base_confidence","tier"],
    "troubleshooting":["title","category","status","created","updated","summary"],
}
STATUS_ENUM = {
    "page":            {"verified","unverified","conflict","archived"},
    "changes":         {"proposed","applied","rejected"},
    "troubleshooting": {"open","resolved"},
}
CATEGORY_ENUM = {"summaries","concepts","knowledge","entities","projects"}
TIER_ENUM = {"core","supporting","peripheral"}
REL_ENUM  = {"uses","contradicts","extends","depends_on","related_to"}
DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')

# 필수 키 존재
for k in REQUIRED[cls]:
    if k not in d or d[k] in (None, "", []):
        errors.append("필수 키 누락: %s" % k)

# category
if "category" in d and d["category"] not in CATEGORY_ENUM:
    errors.append("category enum 위반: %r (허용: %s)" % (d["category"], "|".join(sorted(CATEGORY_ENUM))))
if cls in ("changes","troubleshooting") and d.get("category") not in (None, "projects"):
    errors.append("category는 projects여야 합니다 (클래스②)")

# status (클래스별 enum)
if "status" in d and d["status"] not in STATUS_ENUM[cls]:
    errors.append("status enum 위반: %r (클래스 %s 허용: %s)" % (d["status"], cls, "|".join(sorted(STATUS_ENUM[cls]))))

# summary ≤ 400자
if isinstance(d.get("summary"), str) and len(d["summary"]) > 400:
    errors.append("summary가 400자를 초과합니다 (%d자) — 페이지 분할 검토" % len(d["summary"]))

# tags ≤ 5
if isinstance(d.get("tags"), list) and len(d["tags"]) > 5:
    errors.append("tags가 5개를 초과합니다 (%d개)" % len(d["tags"]))

# 날짜 형식
for k in ("created","updated","status_changed"):
    if k in d and isinstance(d[k], str) and d[k] and not DATE_RE.match(d[k]):
        errors.append("%s 날짜 형식(YYYY-MM-DD) 위반: %r" % (k, d[k]))

# base_confidence 0.0–1.0
if "base_confidence" in d and isinstance(d["base_confidence"], str) and d["base_confidence"]:
    try:
        bc = float(d["base_confidence"])
        if not (0.0 <= bc <= 1.0):
            errors.append("base_confidence 범위(0.0~1.0) 위반: %s" % d["base_confidence"])
    except ValueError:
        errors.append("base_confidence가 숫자가 아닙니다: %r" % d["base_confidence"])

# tier enum (있을 때)
if "tier" in d and isinstance(d["tier"], str) and d["tier"] and d["tier"] not in TIER_ENUM:
    errors.append("tier enum 위반: %r" % d["tier"])

# provenance 합 ≈ 1.0 (있을 때)
prov = d.get("provenance")
if isinstance(prov, dict):
    try:
        s = sum(float(prov.get(k, 0) or 0) for k in ("extracted","inferred","ambiguous"))
        if abs(s - 1.0) > 0.05:
            errors.append("provenance 합이 1.0에서 벗어남: %.3f" % s)
    except ValueError:
        errors.append("provenance 값이 숫자가 아닙니다")

# relationships type enum (있을 때)
rels = d.get("relationships")
if isinstance(rels, list):
    for r in rels:
        if isinstance(r, dict) and "type" in r and r["type"] not in REL_ENUM:
            errors.append("relationship type enum 위반: %r" % r["type"])

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
