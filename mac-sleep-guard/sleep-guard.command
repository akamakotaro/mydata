#!/bin/bash
#
#  sleep-guard.command  —  macOS スリープ防止ツール
#
#  ダブルクリックするだけで caffeinate を起動し、指定した時間だけ
#  Mac がスリープしないようにします。残り時間はリアルタイムに
#  カウントダウン表示され、時間が来ると自動で解除されます。
#
#  使い方:
#    ダブルクリック               → メニューから時間を選ぶ
#    ./sleep-guard.command 90     → 90 分
#    ./sleep-guard.command 1h30m  → 1 時間 30 分
#    ./sleep-guard.command inf    → 無制限（手動で終了するまで）
#
#  ライセンス: MIT
#

set -u

APP_NAME="Sleep Guard"
VERSION="1.0.0"
DEFAULT_INPUT="60"
ADJUST_STEP=$((15 * 60))   # [+] / [-] キーで増減する秒数
BAR_WIDTH=28

CAFFEINATE_PID=""
PREVENT_DISPLAY_SLEEP=1
CURSOR_HIDDEN=0
PANEL_LINES=0
FINISHED_REASON=""

# ---------------------------------------------------------------- 表示まわり

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET="" C_BOLD="" C_DIM="" C_CYAN="" C_GREEN="" C_YELLOW="" C_RED=""
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s\n' "${C_CYAN}$*${C_RESET}"; }
warn() { printf '%s\n' "${C_YELLOW}$*${C_RESET}"; }
err()  { printf '%s\n' "${C_RED}$*${C_RESET}" >&2; }

hide_cursor() { [ -t 1 ] && { printf '\033[?25l'; CURSOR_HIDDEN=1; }; }
show_cursor() { [ "$CURSOR_HIDDEN" = "1" ] && { printf '\033[?25h'; CURSOR_HIDDEN=0; }; }
set_title()   { [ -t 1 ] && printf '\033]0;%s\007' "$1"; }

banner() {
  printf '\n'
  printf '%s\n' "${C_BOLD}${C_CYAN}  ☕️  ${APP_NAME} v${VERSION}${C_RESET}"
  printf '%s\n' "${C_DIM}      Mac をスリープさせないタイマー（caffeinate ラッパー）${C_RESET}"
  printf '\n'
}

# 秒数 → HH:MM:SS
fmt_hms() {
  local t=$1
  printf '%02d:%02d:%02d' $((t / 3600)) $((t % 3600 / 60)) $((t % 60))
}

# 秒数 → 「1時間30分」のような日本語表記
fmt_jp() {
  local t=$1 h m s out=""
  h=$((t / 3600)); m=$((t % 3600 / 60)); s=$((t % 60))
  [ "$h" -gt 0 ] && out="${out}${h}時間"
  [ "$m" -gt 0 ] && out="${out}${m}分"
  [ "$h" -eq 0 ] && [ "$s" -gt 0 ] && out="${out}${s}秒"
  [ -z "$out" ] && out="0秒"
  printf '%s' "$out"
}

# 進捗バー: progress_bar <経過> <合計>
progress_bar() {
  local done_sec=$1 total=$2 filled i bar=""
  if [ "$total" -le 0 ]; then
    printf ''
    return
  fi
  filled=$((done_sec * BAR_WIDTH / total))
  [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  [ "$filled" -lt 0 ] && filled=0
  i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i + 1)); done
  while [ "$i" -lt "$BAR_WIDTH" ]; do bar="${bar}░"; i=$((i + 1)); done
  printf '%s' "$bar"
}

# 指定秒数後の時刻（BSD date）
clock_after() {
  date -v "+$1S" '+%H:%M:%S' 2>/dev/null || date '+%H:%M:%S'
}

# ---------------------------------------------------------------- 入力の解釈

# "90" → 5400 / "1h30m" → 5400 / "inf" → 0（無制限）
# 解釈できなければ 1 を返す
parse_duration() {
  local input="$1" rest total=0 num unit
  local re='^([0-9]+)([hms])(.*)$'

  input=$(printf '%s' "$input" \
    | tr 'A-Z' 'a-z' \
    | tr -d ' ' \
    | sed -e 's/時間/h/g' -e 's/時/h/g' -e 's/分/m/g' -e 's/秒/s/g')

  case "$input" in
    ''|0|inf|infinite|unlimited|forever|none|no|max|無制限)
      printf '0'; return 0 ;;
  esac

  # 数字だけなら「分」とみなす
  case "$input" in
    *[!0-9]*) ;;
    *) printf '%s' $((input * 60)); return 0 ;;
  esac

  rest="$input"
  while [[ $rest =~ $re ]]; do
    num=${BASH_REMATCH[1]}
    unit=${BASH_REMATCH[2]}
    rest=${BASH_REMATCH[3]}
    case "$unit" in
      h) total=$((total + num * 3600)) ;;
      m) total=$((total + num * 60)) ;;
      s) total=$((total + num)) ;;
    esac
  done

  [ -n "$rest" ] && return 1
  [ "$total" -le 0 ] && return 1
  printf '%s' "$total"
}

# ---------------------------------------------------------------- caffeinate

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [ -n "$CAFFEINATE_PID" ] && kill -0 "$CAFFEINATE_PID" 2>/dev/null; then
    kill "$CAFFEINATE_PID" 2>/dev/null
    wait "$CAFFEINATE_PID" 2>/dev/null
  fi
  CAFFEINATE_PID=""
  show_cursor
  set_title "Terminal"
  return $status
}

start_caffeinate() {
  local flags="-is"   # -i: システムのアイドルスリープ抑止 / -s: 電源接続時のスリープ抑止
  [ "$PREVENT_DISPLAY_SLEEP" = "1" ] && flags="-dis"

  caffeinate "$flags" &
  CAFFEINATE_PID=$!

  sleep 0.3
  if ! kill -0 "$CAFFEINATE_PID" 2>/dev/null; then
    err "caffeinate の起動に失敗しました。"
    exit 1
  fi
}

notify() {
  local title="$1" message="$2"
  osascript -e "display notification \"${message}\" with title \"${title}\" sound name \"Glass\"" >/dev/null 2>&1 &
}

# ---------------------------------------------------------------- 画面の描画

draw_panel() {
  local remaining=$1 elapsed=$2 total=$3 paused=$4
  local line1 line2 line3 line4 bar pct state display_state end_at

  if [ "$total" -gt 0 ]; then
    pct=$((elapsed * 100 / total))
    [ "$pct" -gt 100 ] && pct=100
    bar=$(progress_bar "$elapsed" "$total")
    line1=$(printf '  %s残り時間%s  %s%s%s  %s  %3d%%' \
      "$C_DIM" "$C_RESET" "$C_BOLD$C_GREEN" "$(fmt_hms "$remaining")" "$C_RESET" "$bar" "$pct")
    end_at=$(clock_after "$remaining")
    line2=$(printf '  %s終了予定%s  %s%s   %s(経過 %s)%s' \
      "$C_DIM" "$C_RESET" "$end_at" "$C_RESET" "$C_DIM" "$(fmt_hms "$elapsed")" "$C_RESET")
  else
    line1=$(printf '  %s経過時間%s  %s%s%s  %s(無制限モード)%s' \
      "$C_DIM" "$C_RESET" "$C_BOLD$C_GREEN" "$(fmt_hms "$elapsed")" "$C_RESET" "$C_DIM" "$C_RESET")
    line2=$(printf '  %s終了予定%s  %s手動で終了するまで継続します%s' \
      "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET")
  fi

  if [ "$paused" = "1" ]; then
    state="${C_YELLOW}⏸  一時停止中${C_RESET}"
  else
    state="${C_GREEN}☕️ スリープ防止中${C_RESET}"
  fi
  if [ "$PREVENT_DISPLAY_SLEEP" = "1" ]; then
    display_state="ディスプレイ: 常時オン"
  else
    display_state="ディスプレイ: 通常どおり消灯"
  fi
  line3=$(printf '  %s状態%s      %s  %s%s%s' "$C_DIM" "$C_RESET" "$state" "$C_DIM" "$display_state" "$C_RESET")
  line4=$(printf '  %s操作%s      %s[q] 終了   [p] 一時停止/再開   [+] 15分延長   [-] 15分短縮%s' \
    "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET")

  [ "$PANEL_LINES" -gt 0 ] && printf '\033[%dA' "$PANEL_LINES"
  printf '\r\033[K%s\n' "$line1"
  printf '\r\033[K%s\n' "$line2"
  printf '\r\033[K%s\n' "$line3"
  printf '\r\033[K%s\n' "$line4"
  PANEL_LINES=4

  if [ "$total" -gt 0 ]; then
    set_title "☕️ 残り $(fmt_hms "$remaining") — ${APP_NAME}"
  else
    set_title "☕️ $(fmt_hms "$elapsed") 経過 — ${APP_NAME}"
  fi
}

# 1 秒待ちつつキー入力を受け取る（結果を KEY にセット）
wait_key() {
  KEY=""
  if [ -t 0 ]; then
    IFS= read -r -s -n 1 -t 1 KEY 2>/dev/null
  else
    sleep 1
  fi
}

# ---------------------------------------------------------------- メインループ

run_timer() {
  local total=$1
  local now start_epoch end_epoch remaining elapsed paused=0

  start_epoch=$(date +%s)
  end_epoch=$((start_epoch + total))

  printf '\n'
  hide_cursor

  while :; do
    now=$(date +%s)
    elapsed=$((now - start_epoch))

    if [ "$total" -gt 0 ]; then
      remaining=$((end_epoch - now))
      [ "$remaining" -lt 0 ] && remaining=0
      draw_panel "$remaining" "$elapsed" "$total" "$paused"
      if [ "$remaining" -le 0 ]; then
        FINISHED_REASON="timeup"
        break
      fi
    else
      draw_panel 0 "$elapsed" 0 "$paused"
    fi

    wait_key
    case "$KEY" in
      q|Q)
        FINISHED_REASON="user"
        break
        ;;
      p|P)
        if [ "$paused" = "1" ]; then
          paused=0
        else
          paused=1
        fi
        ;;
      +|=)
        if [ "$total" -gt 0 ]; then
          end_epoch=$((end_epoch + ADJUST_STEP))
          total=$((total + ADJUST_STEP))
        fi
        ;;
      -|_)
        if [ "$total" -gt 0 ]; then
          end_epoch=$((end_epoch - ADJUST_STEP))
          total=$((total - ADJUST_STEP))
          now=$(date +%s)
          # 残りが 0 以下にならないよう最低 1 分は残す
          if [ "$end_epoch" -le "$now" ]; then
            end_epoch=$((now + 60))
            total=$((end_epoch - start_epoch))
          fi
        fi
        ;;
    esac

    # 一時停止中は終了時刻を 1 秒ずつ後ろへずらして残り時間を維持する
    if [ "$paused" = "1" ] && [ "$total" -gt 0 ]; then
      end_epoch=$((end_epoch + 1))
      total=$((total + 1))
    fi
  done

  show_cursor
  printf '\n'

  if [ "$FINISHED_REASON" = "timeup" ]; then
    say "${C_GREEN}${C_BOLD}  ✅ 時間になりました。スリープ防止を解除します。${C_RESET}"
    notify "$APP_NAME" "タイマーが終了しました。スリープ防止を解除しました。"
  else
    say "${C_YELLOW}  ⏹  停止しました。スリープ防止を解除します。${C_RESET}"
  fi
}

# ---------------------------------------------------------------- メニュー

# メニューで選ばれた秒数は CHOSEN_SECONDS に入れる
# （コマンド置換で受け取ると画面表示まで取り込んでしまうためグローバルを使う）
CHOSEN_SECONDS=0

choose_duration() {
  local choice input secs

  say "${C_BOLD}  スリープを防止する時間を選んでください${C_RESET}"
  say ""
  say "    ${C_CYAN}1${C_RESET}) 15 分        ${C_CYAN}5${C_RESET}) 3 時間"
  say "    ${C_CYAN}2${C_RESET}) 30 分        ${C_CYAN}6${C_RESET}) 8 時間"
  say "    ${C_CYAN}3${C_RESET}) 1 時間       ${C_CYAN}7${C_RESET}) 無制限（手動で終了）"
  say "    ${C_CYAN}4${C_RESET}) 2 時間       ${C_CYAN}8${C_RESET}) 自分で入力（例: 90 / 1h30m / 45s）"
  say ""

  while :; do
    printf '  選択 [1-8] (既定: 3): '
    if ! IFS= read -r choice; then
      choice="3"
      printf '\n'
    fi
    [ -z "$choice" ] && choice="3"

    case "$choice" in
      1) CHOSEN_SECONDS=900;   return 0 ;;
      2) CHOSEN_SECONDS=1800;  return 0 ;;
      3) CHOSEN_SECONDS=3600;  return 0 ;;
      4) CHOSEN_SECONDS=7200;  return 0 ;;
      5) CHOSEN_SECONDS=10800; return 0 ;;
      6) CHOSEN_SECONDS=28800; return 0 ;;
      7) CHOSEN_SECONDS=0;     return 0 ;;
      8)
        while :; do
          printf '  時間を入力 (例: 90=90分 / 2h / 1h30m / 45s / inf): '
          if ! IFS= read -r input; then
            input="$DEFAULT_INPUT"
            printf '\n'
          fi
          [ -z "$input" ] && input="$DEFAULT_INPUT"
          if secs=$(parse_duration "$input"); then
            CHOSEN_SECONDS=$secs
            return 0
          fi
          warn "  入力を解釈できませんでした: $input"
        done
        ;;
      *) warn "  1〜8 の数字を入力してください。" ;;
    esac
  done
}
ask_display_sleep() {
  local ans
  printf '  ディスプレイも消灯させない？ [Y/n]: '
  if ! IFS= read -r ans; then
    ans=""
    printf '\n'
  fi
  case "$(printf '%s' "$ans" | tr 'A-Z' 'a-z')" in
    n|no) PREVENT_DISPLAY_SLEEP=0 ;;
    *)    PREVENT_DISPLAY_SLEEP=1 ;;
  esac
}

usage() {
  cat <<USAGE
${APP_NAME} v${VERSION} — macOS のスリープを一定時間だけ防止します。

使い方:
  sleep-guard.command [時間] [オプション]

時間の指定:
  90            90 分
  2h            2 時間
  1h30m         1 時間 30 分
  45s           45 秒
  inf, 0        無制限（手動で終了するまで）
  省略          対話メニューから選択

オプション:
  -n, --no-display   ディスプレイの消灯は許可する（システムのスリープのみ防止）
  -h, --help         このヘルプを表示

実行中のキー操作:
  q  終了      p  一時停止/再開      +  15 分延長      -  15 分短縮
USAGE
}

# ---------------------------------------------------------------- エントリ

main() {
  local arg duration_input="" total

  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -h|--help)       usage; exit 0 ;;
      -n|--no-display) PREVENT_DISPLAY_SLEEP=0 ;;
      -*)              err "不明なオプション: $arg"; usage; exit 2 ;;
      *)               duration_input="$arg" ;;
    esac
    shift
  done

  if [ "$(uname -s)" != "Darwin" ]; then
    err "このスクリプトは macOS 専用です（現在: $(uname -s)）。"
    exit 1
  fi
  if ! command -v caffeinate >/dev/null 2>&1; then
    err "caffeinate コマンドが見つかりません。macOS 標準のコマンドです。"
    exit 1
  fi

  clear 2>/dev/null
  banner

  if [ -n "$duration_input" ]; then
    if ! total=$(parse_duration "$duration_input"); then
      err "時間を解釈できませんでした: $duration_input"
      say ""
      usage
      exit 2
    fi
  else
    choose_duration
    total=$CHOSEN_SECONDS
    say ""
    ask_display_sleep
  fi

  trap cleanup EXIT
  trap 'FINISHED_REASON=signal; exit 0' INT TERM

  start_caffeinate

  say ""
  if [ "$total" -gt 0 ]; then
    info "  ▶ $(fmt_jp "$total") のあいだスリープを防止します（終了予定 $(clock_after "$total")）"
  else
    info "  ▶ 無制限モードでスリープを防止します（[q] または Ctrl-C で終了）"
  fi

  run_timer "$total"

  cleanup
  say ""
  if [ -t 0 ]; then
    printf '%s' "${C_DIM}  Enter キーでウインドウを閉じます...${C_RESET}"
    IFS= read -r _ || true
    printf '\n'
  fi
}

main "$@"
