#!/usr/bin/env bash

set -o pipefail

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  CYAN=""
  RESET=""
fi

usage() {
  cat <<'EOF'
Kullanım: cleanup.sh [seçenekler]

Seçenek yoksa etkileşimli mod çalışır (terminal gerekir).

  -l, --list              Raporu yazdır, hiçbir şey silme
      --json              Raporu JSON olarak yazdır
      --trash <idler>     Verilen kimlikleri Çöpe taşı (örn: --trash 2,3)
      --delete <idler>    Verilen kimlikleri kalıcı sil (--yes ile)
  -y, --yes               Kalıcı silmeyi onayla
  -h, --help              Bu yardımı göster

Ortam değişkenleri:
  LARGE_FILE_GB           Büyük dosya eşiği (varsayılan 1)
  MAX_LARGE_FILES         Listelenecek en büyük dosya sayısı (varsayılan 20)
EOF
}

human_kb() {
  awk -v k="$1" 'BEGIN {
    split("KB MB GB TB PB", u, " ")
    i = 1
    while (k >= 1024 && i < 5) { k /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), k, u[i]
  }'
}

dir_size_kb() {
  du -sk "$1" 2>/dev/null | awk '{print $1}'
}

dir_item_count() {
  find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

category_names=(
  "Çöp Kutusu"
  "Uygulama önbellekleri"
  "Kullanıcı logları"
  "Xcode DerivedData"
  "Xcode iOS DeviceSupport"
  "Xcode Archives"
  "npm önbelleği"
  "Genel önbellek (~/.cache)"
)

category_paths=(
  "$HOME/.Trash"
  "$HOME/Library/Caches"
  "$HOME/Library/Logs"
  "$HOME/Library/Developer/Xcode/DerivedData"
  "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  "$HOME/Library/Developer/Xcode/Archives"
  "$HOME/.npm/_cacache"
  "$HOME/.cache"
)

category_count=${#category_names[@]}

item_names=()
item_paths=()
item_sizes=()
item_counts=()
item_kinds=()
chosen=()
total_kb=0
large_threshold_gb=1
large_max_files=20
disk_total_kb=0
disk_used_kb=0
disk_avail_kb=0
disk_capacity="?"

scan_categories() {
  local i path kb cnt
  for i in "${!category_names[@]}"; do
    path="${category_paths[$i]}"
    if [[ -e "$path" ]]; then
      kb=$(dir_size_kb "$path")
      kb=${kb:-0}
      cnt=$(dir_item_count "$path")
    else
      kb=0
      cnt=0
    fi
    item_names+=("${category_names[$i]}")
    item_paths+=("$path")
    item_sizes+=("$kb")
    item_counts+=("$cnt")
    item_kinds+=("category")
    total_kb=$((total_kb + kb))
  done
}

scan_large_files() {
  local threshold max tmp prune_file bytes path kb displayed count f
  threshold="${LARGE_FILE_GB:-1}"
  [[ "$threshold" =~ ^[0-9]+$ ]] && (( threshold > 0 )) || threshold=1
  large_threshold_gb=$threshold

  max="${MAX_LARGE_FILES:-20}"
  [[ "$max" =~ ^[0-9]+$ ]] && (( max > 0 )) || max=20
  large_max_files=$max

  tmp=$(mktemp "${TMPDIR:-/tmp}/cleanup-large.XXXXXX") || return 0

  printf '%sBüyük dosyalar taranıyor (>%s GB)...%s\n' "$DIM" "$threshold" "$RESET" >&2

  prune=("$HOME/.Trash" "$HOME/Library/Caches" "$HOME/Library/Logs")
  prune+=("$HOME/Library/Developer/Xcode/DerivedData")
  prune+=("$HOME/Library/Developer/Xcode/iOS DeviceSupport")
  prune+=("$HOME/Library/Developer/Xcode/Archives")
  prune+=("$HOME/.npm" "$HOME/.cache" "$HOME/Library/CloudStorage")

  prune_file=()
  for path in "${prune[@]}"; do
    prune_file+=(-path "$path" -prune -o)
  done

  find "$HOME" "${prune_file[@]}" -type f -size "+${threshold}G" -print 2>/dev/null |
    while IFS= read -r f; do
      bytes=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
      [[ -n "$bytes" ]] || continue
      printf '%s\t%s\n' "$bytes" "$f"
    done |
    sort -t $'\t' -k1,1nr |
    head -n "$max" > "$tmp"

  count=0
  while IFS=$'\t' read -r bytes path; do
    [[ -n "$path" ]] || continue
    kb=$((bytes / 1024))
    item_names+=("$(basename "$path")")
    item_paths+=("$path")
    item_sizes+=("$kb")
    item_counts+=(1)
    item_kinds+=("file")
    total_kb=$((total_kb + kb))
    count=$((count + 1))
  done < "$tmp"

  displayed=$count
  rm -f "$tmp"
}

scan_all() {
  read -r disk_total_kb disk_used_kb disk_avail_kb disk_capacity <<< "$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $2, $3, $4, $5}')"
  disk_total_kb=${disk_total_kb:-0}
  disk_used_kb=${disk_used_kb:-0}
  disk_avail_kb=${disk_avail_kb:-0}
  disk_capacity=${disk_capacity:-?}
  scan_categories
  scan_large_files
}

print_report() {
  local i idx display listed
  printf '%s\n' "${BOLD}Disk kullanımı taraması${RESET}"
  printf 'Disk: %s dolu / %s (%s kullanımda)\n' "$(human_kb "$disk_used_kb")" "$(human_kb "$disk_total_kb")" "$disk_capacity"
  printf '%s\n\n' "${DIM}Silme işlemi sizin onayınız olmadan yapılmaz.${RESET}"

  for ((i = 0; i < category_count; i++)); do
    printf ' %2d) %-31s %10s  %s\n' "$((i + 1))" "${item_names[$i]}" "$(human_kb "${item_sizes[$i]}")" "${DIM}(${item_counts[$i]} öğe)${RESET}"
  done

  printf '\n%sBüyük dosyalar (>%s GB):%s\n' "$BOLD" "$large_threshold_gb" "$RESET"
  listed=$(( ${#item_names[@]} - category_count ))
  if (( listed == 0 )); then
    printf ' %sBulunamadı.%s\n' "$DIM" "$RESET"
  else
    for ((idx = category_count; idx < ${#item_names[@]}; idx++)); do
      display="${item_paths[$idx]}"
      display="${display/#$HOME/~}"
      printf ' %2d) %10s  %s\n' "$((idx + 1))" "$(human_kb "${item_sizes[$idx]}")" "$display"
    done
    if (( listed >= large_max_files )); then
      printf ' %sEn büyük %d dosya gösteriliyor.%s\n' "$DIM" "$large_max_files" "$RESET"
    fi
  fi

  printf '\n%sToplam temizlenebilir alan: %s%s\n' "$BOLD" "$(human_kb "$total_kb")" "$RESET"
}

print_json() {
  local i first=1
  printf '{\n'
  printf '  "disk": {"total_kb": %s, "used_kb": %s, "available_kb": %s, "capacity": "%s"},\n' \
    "$disk_total_kb" "$disk_used_kb" "$disk_avail_kb" "$disk_capacity"
  printf '  "total_reclaimable_kb": %s,\n' "$total_kb"
  printf '  "large_file_threshold_gb": %s,\n' "$large_threshold_gb"
  printf '  "items": ['
  for i in "${!item_names[@]}"; do
    if (( first == 1 )); then
      first=0
    else
      printf ','
    fi
    printf '\n    {"id": %d, "kind": "%s", "name": "%s", "path": "%s", "size_kb": %s, "entries": %s}' \
      "$((i + 1))" "${item_kinds[$i]}" "$(json_escape "${item_names[$i]}")" \
      "$(json_escape "${item_paths[$i]}")" "${item_sizes[$i]}" "${item_counts[$i]}"
  done
  printf '\n  ]\n}\n'
}

parse_selection() {
  local input="$1" allow_all="$2" part idx seen
  local -a parts
  chosen=()

  if [[ "$allow_all" == "1" && ( "$input" == "hepsi" || "$input" == "Hepsi" ) ]]; then
    for ((idx = 0; idx < category_count; idx++)); do
      chosen+=("$idx")
    done
    return 0
  fi

  IFS=', ' read -r -a parts <<< "$input"
  seen=" "
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    if ! [[ "$part" =~ ^[0-9]+$ ]] || (( part < 1 || part > ${#item_names[@]} )); then
      printf '%sGeçersiz seçim: %s (1-%d arası)%s\n' "$RED" "$part" "${#item_names[@]}" "$RESET" >&2
      return 1
    fi
    idx=$((part - 1))
    case "$seen" in
      *" $idx "*) continue ;;
    esac
    seen="$seen$idx "
    chosen+=("$idx")
  done

  if (( ${#chosen[@]} == 0 )); then
    printf 'Seçim yapılmadı.\n' >&2
    return 1
  fi
  return 0
}

print_chosen() {
  local idx total=0
  printf '\n%sSeçilenler:%s\n' "$BOLD" "$RESET"
  for idx in "${chosen[@]}"; do
    total=$((total + ${item_sizes[$idx]}))
    printf ' - %-31s %10s\n' "${item_names[$idx]}" "$(human_kb "${item_sizes[$idx]}")"
    if [[ "${item_kinds[$idx]}" == "file" ]]; then
      printf '   %s%s%s\n' "$DIM" "${item_paths[$idx]}" "$RESET"
    fi
  done
  printf '%sToplam: %s%s\n\n' "$BOLD" "$(human_kb "$total")" "$RESET"
}

perform_deletion() {
  local mode="$1" freed=0 idx path name dest
  for idx in "${chosen[@]}"; do
    path="${item_paths[$idx]}"
    name="${item_names[$idx]}"

    if [[ -z "$path" || "$path" == "$HOME" || "$path" != "$HOME/"* ]]; then
      printf ' - %s: güvenlik nedeniyle atlandı\n' "$name" >&2
      continue
    fi

    if [[ ! -e "$path" ]]; then
      printf ' - %s: bulunamadı, atlandı\n' "$name" >&2
      continue
    fi

    if [[ "$path" == "$HOME/.Trash" ]]; then
      if find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null; then
        freed=$((freed + ${item_sizes[$idx]}))
        printf ' %s✓%s %s temizlendi\n' "$GREEN" "$RESET" "$name"
      else
        printf ' %s✗%s %s temizlenemedi\n' "$RED" "$RESET" "$name"
      fi
      continue
    fi

    if [[ "$mode" == "delete" ]]; then
      if rm -rf -- "$path" 2>/dev/null; then
        freed=$((freed + ${item_sizes[$idx]}))
        printf ' %s✓%s %s kalıcı olarak silindi\n' "$GREEN" "$RESET" "$name"
      else
        printf ' %s✗%s %s silinemedi\n' "$RED" "$RESET" "$name"
      fi
    else
      mkdir -p "$HOME/.Trash"
      dest="$HOME/.Trash/$(basename "$path").$(date +%Y%m%d%H%M%S).$RANDOM"
      if mv -- "$path" "$dest" 2>/dev/null; then
        freed=$((freed + ${item_sizes[$idx]}))
        printf ' %s✓%s %s çöpe taşındı\n' "$GREEN" "$RESET" "$name"
      else
        printf ' %s✗%s %s çöpe taşınamadı\n' "$RED" "$RESET" "$name"
      fi
    fi
  done

  printf '\n%sTemizlenen: %s%s\n' "$BOLD" "$(human_kb "$freed")" "$RESET"
  if [[ "$mode" == "trash" && "$freed" -gt 0 ]]; then
    printf "%sNot: Alanın gerçekten boşalması için Çöp Kutusu'nu boşaltmayı unutmayın.%s\n" "$YELLOW" "$RESET"
  fi
}

action="interactive"
ids=""
mode="trash"
assume_yes=0

while (( $# > 0 )); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -l | --list)
      action="list"
      ;;
    --json)
      action="json"
      ;;
    --trash)
      action="remove"
      mode="trash"
      shift
      ids="${1:-}"
      if [[ -z "$ids" ]]; then
        printf '%s\n' "--trash için kimlik listesi gerekli (örn: --trash 2,3)" >&2
        exit 1
      fi
      ;;
    --delete)
      action="remove"
      mode="delete"
      shift
      ids="${1:-}"
      if [[ -z "$ids" ]]; then
        printf '%s\n' "--delete için kimlik listesi gerekli (örn: --delete 2,3 --yes)" >&2
        exit 1
      fi
      ;;
    -y | --yes)
      assume_yes=1
      ;;
    *)
      printf 'Bilinmeyen seçenek: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

scan_all

case "$action" in
  json)
    print_json
    exit 0
    ;;
  list)
    print_report
    exit 0
    ;;
  remove)
    if [[ "$mode" == "delete" && "$assume_yes" -ne 1 ]]; then
      printf 'Kalıcı silme için --yes ekleyin. Önce --list ile kontrol edin.\n' >&2
      exit 1
    fi
    if ! parse_selection "$ids" 0; then
      exit 1
    fi
    print_chosen
    perform_deletion "$mode"
    exit 0
    ;;
esac

print_report

if [[ ! -t 0 ]]; then
  printf '\n%sEtkileşimli mod için bir terminalde çalıştırın.%s\n' "$DIM" "$RESET"
  printf 'Silmek için: ./cleanup.sh --trash <idler>\n'
  exit 0
fi

selection=""
while [[ -z "$selection" ]]; do
  read -r -p "Silmek istediğiniz kategoriler (örn: 1,3 / hepsi = kategoriler / q): " selection
  case "$selection" in
    q | Q)
      printf 'İptal edildi.\n'
      exit 0
      ;;
  esac
done

if ! parse_selection "$selection" 1; then
  exit 1
fi
print_chosen

printf '%sSilme yöntemi:%s\n' "$BOLD" "$RESET"
printf '  1) Çöpe taşı (geri alınabilir)\n'
printf '  2) Kalıcı sil (geri alınamaz)\n'
read -r -p "Seçim [1]: " mode
mode=${mode:-1}

case "$mode" in
  1)
    mode=trash
    read -r -p "Çöpe taşınsın mı? [e/H]: " go
    [[ "$go" == "e" || "$go" == "E" ]] || { printf 'İptal edildi.\n'; exit 0; }
    ;;
  2)
    mode=delete
    printf '%sBu işlem geri alınamaz. Onaylamak için SIL yazın: %s' "$RED" "$RESET"
    read -r confirm
    [[ "$confirm" == "SIL" ]] || { printf 'İptal edildi.\n'; exit 0; }
    ;;
  *)
    printf '%sGeçersiz seçim.%s\n' "$RED" "$RESET" >&2
    exit 1
    ;;
esac

perform_deletion "$mode"
