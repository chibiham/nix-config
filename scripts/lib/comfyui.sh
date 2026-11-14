# shellcheck shell=bash
# ComfyUIのサービスを起動し直すスクリプト（update-comfyui-ubuntu.sh、install-comfyui-ubuntu.sh --unit-only）が共有する関数。
# source して使う。JSONは jq があれば jq、なければ python3 で読む（dekahamuntu・chibihamuntu には Nix の jq がある）。

# comfy_queue_is_idle <port>
# キュー（/queue）に実行中・待ちがなければ 0。あれば 1（何を止めるかは呼び出し側が決める）。
# 止まっているとみなして 0 を返すのは、つながらなかった（curl の終了コード 7）ときだけ。
# タイムアウト（28）・HTTP の誤り（22）などは、生成中で応答が遅いだけかもしれないので、確かめられなかったとして 1。
# art-studio のループは項目の合間にキューが空になる。止め方の手順は docs に書く。
comfy_queue_is_idle() {
  local port="$1" url body counts running pending rc=0
  url="http://127.0.0.1:$port/queue"
  if ! command -v curl >/dev/null; then
    echo "curl がないので ComfyUI のキューを確かめられません（確かめずに進めるなら --force）" >&2
    return 1
  fi
  body="$(curl -fsS --max-time 5 "$url" 2>/dev/null)" || rc=$?
  if ((rc == 7)); then
    echo "ComfyUI（$url）につながらないので、止まっているものとして進みます"
    return 0
  fi
  if ((rc != 0)); then
    echo "ComfyUI のキュー（$url）を確かめられませんでした（curl の終了コード $rc。28 はタイムアウト、22 は HTTP の誤り）。" >&2
    echo "何も変えずに止めます。確かめずに進めるなら --force" >&2
    return 1
  fi
  if command -v jq >/dev/null; then
    counts="$(jq -r '"\(.queue_running | length) \(.queue_pending | length)"' <<<"$body" 2>/dev/null)" || counts=""
  elif command -v python3 >/dev/null; then
    counts="$(python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(len(d["queue_running"]), len(d["queue_pending"]))
' <<<"$body" 2>/dev/null)" || counts=""
  else
    echo "jq も python3 もないので ComfyUI のキューを読めません（確かめずに進めるなら --force）" >&2
    return 1
  fi
  read -r running pending <<<"$counts"
  if [[ ! "$running" =~ ^[0-9]+$ ]] || [[ ! "$pending" =~ ^[0-9]+$ ]]; then
    echo "ComfyUI のキュー（$url）の応答を読めませんでした（確かめずに進めるなら --force）" >&2
    return 1
  fi
  if ((running > 0 || pending > 0)); then
    echo "ComfyUI のキューが空ではありません（実行中 $running、待ち $pending）。何も変えずに止めます" >&2
    echo "終わってから流し直すか、--force で確かめずに進めます" >&2
    return 1
  fi
  echo "ComfyUI のキューは空です"
}

# comfy_wait_ready <port> <秒>
# /system_stats が返るまで待ち、comfyui_version を表示する。返らなければ 1。
# 起動し直しのあと、拡張（custom_nodes）の読み込みに時間がかかる。
comfy_wait_ready() {
  local port="$1" timeout="$2" url body version start
  url="http://127.0.0.1:$port/system_stats"
  start=$SECONDS
  while ((SECONDS - start < timeout)); do
    if body="$(curl -fsS --max-time 5 "$url" 2>/dev/null)"; then
      if command -v jq >/dev/null; then
        version="$(jq -r '.system.comfyui_version // "不明"' <<<"$body" 2>/dev/null)" || version="不明"
      else
        version="$(python3 -I -c '
import json, sys
print(json.load(sys.stdin).get("system", {}).get("comfyui_version", "不明"))
' <<<"$body" 2>/dev/null)" || version="不明"
      fi
      echo "ComfyUI が応答しました（$((SECONDS - start)) 秒）: comfyui_version $version"
      return 0
    fi
    sleep 3
  done
  echo "ComfyUI が ${timeout} 秒たっても応答しません（$url）。journalctl --user -u comfyui -n 100 で確かめてください" >&2
  return 1
}
