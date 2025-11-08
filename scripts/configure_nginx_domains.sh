#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_PATH="${NGINX_TEMPLATE:-nginx/conf.d/cpx_exchange.temp.conf}"
OUTPUT_PATH="${NGINX_OUTPUT:-nginx/conf.d/cpx_exchange.conf}"

if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "未找到 Nginx 模板文件: $TEMPLATE_PATH" >&2
  exit 1
fi

trim() {
  local var="$1"
  # shellcheck disable=SC2001
  var=$(echo "$var" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  printf '%s\n' "$var"
}

sanitize_domain() {
  local value="$1"
  value=$(trim "$value")
  value=${value#http://}
  value=${value#https://}
  value=${value#/}
  value=${value%.}
  printf '%s\n' "$value"
}

prompt_main_domain() {
  local main_domain=""
  while true; do
    read -r -p "请输入部署主域名（例如 example.com）: " main_domain || true
    main_domain=$(sanitize_domain "$main_domain")
    if [ -n "$main_domain" ]; then
      echo "$main_domain"
      return
    fi
    echo "主域名不能为空，请重新输入。"
  done
}

prompt_sub_prefix() {
  local label="$1"
  local default_value="$2"
  local input=""
  read -r -p "请输入 ${label} 的二级域名前缀（默认: ${default_value}）: " input || true
  input=$(trim "$input")
  input=${input#.}
  input=${input%.}
  if [ -z "$input" ]; then
    input="$default_value"
  fi
  echo "$input"
}

main() {
  local main_domain
  main_domain=$(prompt_main_domain)

  local placeholders=("api_domain" "manager_domain" "h5_domain" "app_domain")
  local labels=("API 服务" "管理后台" "H5 站点" "APP 站点")
  local defaults=("api" "manager" "h5" "app")
  local final_domains=()
  local replacements=()

  local count=${#placeholders[@]}
  local i
  for ((i = 0; i < count; i++)); do
    local prefix
    prefix=$(prompt_sub_prefix "${labels[$i]}" "${defaults[$i]}")
    local domain="${prefix}.${main_domain}"
    final_domains+=("$domain")
    replacements+=("${placeholders[$i]}=${domain}")
  done

  python3 - "$TEMPLATE_PATH" "$OUTPUT_PATH" "${replacements[@]}" <<'PY'
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1]).resolve()
output_path = pathlib.Path(sys.argv[2]).resolve()

replacements = {}
for item in sys.argv[3:]:
    if "=" not in item:
        continue
    key, value = item.split("=", 1)
    replacements[key] = value

content = template_path.read_text(encoding="utf-8")
for key, value in replacements.items():
    content = content.replace(f"{{{key}}}", value)

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(content, encoding="utf-8")
PY

  echo ""
  echo "已根据 ${TEMPLATE_PATH} 生成域名配置到 ${OUTPUT_PATH}:"
  for ((i = 0; i < count; i++)); do
    printf "  %s -> %s\n" "${placeholders[$i]}" "${final_domains[$i]}"
  done
}

main
