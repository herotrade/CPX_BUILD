#!/usr/bin/env bash
set -euo pipefail

ROOT_TEMPLATE="${RUNNER_COMPOSE_TEMPLATE:-runner-compose.temp.yml}"
DEFAULT_TEMPLATES=(
  "redis_market/redis.temp.conf"
  "redis_cache/redis.temp.conf"
  "app/CPX_EXCHANGE/prod.temp.env"
)

if ! command -v python3 >/dev/null 2>&1; then
  echo "需要 python3 来生成随机密码，请先安装 python3。" >&2
  exit 1
fi

declare -a TEMPLATE_FILES=("$ROOT_TEMPLATE")
if [ "$#" -gt 0 ]; then
  TEMPLATE_FILES+=("$@")
else
  TEMPLATE_FILES+=("${DEFAULT_TEMPLATES[@]}")
fi

# 去重同时保持顺序（兼容旧版 bash）
dedup_files=()
for file in "${TEMPLATE_FILES[@]}"; do
  skip=0
  if [ "${#dedup_files[@]}" -gt 0 ]; then
    for existing in "${dedup_files[@]}"; do
      if [ "$existing" = "$file" ]; then
        skip=1
        break
      fi
    done
  fi
  if [ "$skip" -eq 0 ]; then
    dedup_files+=("$file")
  fi
done
TEMPLATE_FILES=("${dedup_files[@]}")

missing=0
for file in "${TEMPLATE_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "未找到模板文件: $file" >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  exit 1
fi

python3 - "$ROOT_TEMPLATE" "${TEMPLATE_FILES[@]}" <<'PY'
import pathlib
import re
import secrets
import string
import sys
import base64

if len(sys.argv) < 3:
    print("缺少模板文件参数，脚本未执行。", file=sys.stderr)
    sys.exit(1)

root_template = pathlib.Path(sys.argv[1]).resolve()
template_paths = []
seen = set()
for path_str in sys.argv[2:]:
    path = pathlib.Path(path_str).resolve()
    if path not in seen:
        template_paths.append(path)
        seen.add(path)

pattern = re.compile(r"\{([A-Za-z0-9_]+_(?:password|secret|sec))\}")
root_content = root_template.read_text(encoding="utf-8")
placeholders = []
seen_names = set()

def add_placeholders(names):
    for name in names:
        if name not in seen_names:
            placeholders.append(name)
            seen_names.add(name)

add_placeholders(pattern.findall(root_content))

for extra_path in template_paths:
    add_placeholders(pattern.findall(extra_path.read_text(encoding="utf-8")))

if not placeholders:
    print(f"未找到可替换的占位符，文件未修改。")
    sys.exit(0)

alphabet = string.ascii_letters + string.digits

def gen_password(length: int = 32) -> str:
    return "".join(secrets.choice(alphabet) for _ in range(length))

def gen_secret(name: str) -> str:
    lower = name.lower()
    if "jwt" in lower:
        raw = secrets.token_bytes(32)
        return base64.urlsafe_b64encode(raw).decode("ascii")
    return gen_password()

unique_names = list(dict.fromkeys(placeholders))
replacements = {name: gen_secret(name) for name in unique_names}

def target_path(path: pathlib.Path) -> pathlib.Path:
    name = path.name
    if ".temp" in name:
        name = name.replace(".temp", "", 1)
    return path.with_name(name)

results = []

for src_path in template_paths:
    text = src_path.read_text(encoding="utf-8")
    for key, value in replacements.items():
        text = text.replace(f"{{{key}}}", f"\"{value}\"")
    dest_path = target_path(src_path)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    dest_path.write_text(text, encoding="utf-8")
    results.append((src_path, dest_path))

print(f"已根据 {root_template} 生成随机密码并写入以下文件：")
for src, dest in results:
    print(f"  {src} -> {dest}")

print("\n生成的密码如下：")
for name, password in replacements.items():
    print(f"  {name}: {password}")
PY

ENV_TEMPLATE="app/CPX_EXCHANGE/prod.temp.env"
ENV_OUTPUT="${ENV_TEMPLATE/.temp/}"
ENV_DEST="app/CPX_EXCHANGE/.env"

if [ -f "$ENV_OUTPUT" ]; then
  cp "$ENV_OUTPUT" "$ENV_DEST"
  echo "已生成环境文件: ${ENV_DEST}"
fi
