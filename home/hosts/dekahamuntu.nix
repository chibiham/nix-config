# dekahamuntu固有のHome Manager設定
# AMD Ryzen / RTX 5060 Ti 16GB ×2（Blackwell、NVLinkなし）/ DDR5 64GB / Ubuntu 24.04
#
# llama.cppのCUDAの世代（12.0）は flake.nix の mkLinuxHome の cudaCapabilities で指定する。
# スクリプト側のホストの設定は hosts/ubuntu/dekahamuntu.env。
{ pkgs, ... }:

let
  # GPU 0 = ComfyUI（comfyui.service、8188）、GPU 1 = 2 つ目の ComfyUI（comfyui-gpu1.service、8189）と Qwen（qwen38.service）を既定にし、
  # 必要なときだけ2枚を束ねたQwen（qwen38-dual.service。2 つの ComfyUI とは排他）に切り替える。
  # 2 つ目の ComfyUI は hosts/ubuntu/dekahamuntu.env の COMFY_EXTRA_INSTANCES（gpu1:8189:1）から install-comfyui-ubuntu.sh が書く。
  # 名前・ポートを変えたら、下の comfyGpu1・comfyGpu1Port も揃える。
  # 1 つ目の ComfyUI には2枚とも見せていて、MiniMax H3 Image のテキストエンコーダーの計算は GPU 1 で回す（Select CLIP Device = gpu:1、issue 5）。
  # 重みは RAM に置かれ、GPU 1 はエンコードのあいだだけ約 1.2〜1.5GB 使う（本番で確かめた、2026-11-14）。
  # Qwen のモデルが GPU 1 に載っているとその計算が OutOfMemoryError（device 1）になるので、image-dual で Qwen のモデルを降ろす。
  # split は ComfyUI のモデルを降ろし、主に ComfyUI が RAM に持っている重みを Qwen（Flash-Next は RAM に約 52GB）に空ける。
  # unitのGPUの割り当てと Conflicts= は scripts/install-*-ubuntu.sh が hosts/ubuntu/dekahamuntu.env から書く。
  comfyGpu1 = "comfyui-gpu1.service";
  comfyGpu1Port = "8189";
  ai-mode = pkgs.writeShellScriptBin "ai-mode" ''
    set -euo pipefail

    usage() {
      cat >&2 <<'EOF'
    usage: ai-mode {split|image-dual|llm-dual|applio|stop|status}
      split       GPU 0 = ComfyUI（8188）、GPU 1 = 2 つ目の ComfyUI（8189）と Qwen（既定。再起動後もこの形）。
                  2 つの ComfyUI が載せているモデルを降ろさせる（RAMの重みをQwenに空ける）
      image-dual  splitの形にしたうえでQwenのモデルと 2 つ目の ComfyUI（8189）のモデルを降ろし、
                  GPU 1 をH3 Imageのテキストエンコーダーの計算（Select CLIP Device = gpu:1）と 2 つ目の ComfyUI に空ける
                  （Routerは止めない。次にQwenへ問うと読み込み直す）。
                  Qwen のモデルが降りたのを確かめてから戻る（確かめられなければ失敗で終わる）
      llm-dual    2 つの ComfyUI とQwen（1枚）を止め、2枚を束ねたQwenを起動
      applio      GPU 0 でApplioを起動（ComfyUI（8188）は止まる。GPU 1 の 2 つ目の ComfyUI とQwenはそのまま）
      stop        すべて停止（LoRA学習は止めない）
      status      各サービスと学習の状態
    EOF
      exit 2
    }

    # Router（qwen38・qwen38-dual のどちらか、8080）のロード済みモデルを降ろす（loaded・sleeping・loading）。
    # split・llm-dual で、束ねたQwenを止める前に使う（VRAMを早く空ける）。降りるのを待たず、失敗しても続ける
    # （このあと unit を止めるので、待たなくてもVRAMは空く）。image-dual は下の unload_models_wait を使う
    unload_models() {
      local models model
      models=$(${pkgs.curl}/bin/curl -fsS --max-time 5 http://127.0.0.1:8080/models 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.data[] | select(.status.value != "unloaded") | .id') || return 0
      for model in $models; do
        echo "Qwenのモデルをアンロード: $model" >&2
        ${pkgs.curl}/bin/curl -fsS --max-time 30 -H 'Content-Type: application/json' \
          -d "{\"model\":\"$model\"}" http://127.0.0.1:8080/models/unload >/dev/null || true
      done
    }

    # Router の /models のうち status が unloaded でないものを「id status」で1行ずつ出す。
    # Router が応答しない・JSONが読めないときは 1
    router_models() {
      local body
      body=$(${pkgs.curl}/bin/curl -fsS --max-time 5 http://127.0.0.1:8080/models 2>/dev/null) || return 1
      ${pkgs.jq}/bin/jq -r '.data[] | select(.status.value != "unloaded") | "\(.id) \(.status.value)"' <<<"$body" 2>/dev/null
    }

    # image-dual 用: Qwen のモデルを降ろし、全部の status が unloaded になるまで待つ。
    # llama.cpp（0.6.0）の Router の /models/unload は停止を頼むだけで、子プロセスの終了・VRAMの解放を待たずに返る。
    # 待たずに戻ると、直後の H3 Image（gpu:1）が GPU 1 に残った Qwen とぶつかって OutOfMemoryError になる。
    # unload_models と違い、確かめられなければ失敗（1）で終わる。
    # 上限（秒）: AI_MODE_UNLOAD_TIMEOUT（降りるのを待つ、既定 60）、AI_MODE_ROUTER_TIMEOUT（Router が応答するのを待つ、既定 20。
    # qwen38 を起動したばかりのとき。起動直後の Router はモデルを載せていない）
    unload_models_wait() {
      local timeout="''${AI_MODE_UNLOAD_TIMEOUT:-60}" router_timeout="''${AI_MODE_ROUTER_TIMEOUT:-20}"
      local remaining model status waited=0
      until remaining=$(router_models); do
        if ((waited >= router_timeout)); then
          echo "Qwen の Router（127.0.0.1:8080）に聞けないので、GPU 1 が空いたかを確かめられません（$router_timeout 秒待った）" >&2
          return 1
        fi
        sleep 1
        waited=$((waited + 1))
      done
      if [[ -z "$remaining" ]]; then
        echo "Qwenのモデルは載っていません" >&2
        return 0
      fi
      while read -r model status; do
        echo "Qwenのモデルをアンロード: $model（$status）" >&2
        if ! ${pkgs.curl}/bin/curl -fsS --max-time 30 -H 'Content-Type: application/json' \
          -d "{\"model\":\"$model\"}" http://127.0.0.1:8080/models/unload >/dev/null; then
          echo "Qwenのモデル $model のアンロードを頼めませんでした" >&2
          return 1
        fi
      done <<<"$remaining"
      waited=0
      while ((waited < timeout)); do
        sleep 1
        waited=$((waited + 1))
        if remaining=$(router_models); then
          if [[ -z "$remaining" ]]; then
            echo "GPU 1 が空きました（Qwen のモデルが降りるまで $waited 秒）" >&2
            return 0
          fi
        else
          remaining="（Router に聞けません）"
        fi
      done
      echo "Qwen のモデルが $timeout 秒たっても降りていません:" >&2
      echo "$remaining" >&2
      echo "H3 Image を投げる前にもう一度 ai-mode image-dual を流すか、ai-mode status で確かめてください" >&2
      return 1
    }

    # ComfyUIが載せているモデルを降ろさせる。実行中のものが終わってから降ろす（キューは消えない）。
    # 引数はポート（既定は 2 つとも: 8188 と ${comfyGpu1Port}）。応答しなくても（止まっている・起動中）続ける
    free_comfy() {
      local port ports=("$@")
      if (($# == 0)); then
        ports=(8188 ${comfyGpu1Port})
      fi
      for port in "''${ports[@]}"; do
        echo "ComfyUI（''${port}）のモデルを降ろします" >&2
        ${pkgs.curl}/bin/curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' \
          -d '{"unload_models":true,"free_memory":true}' "http://127.0.0.1:$port/free" >/dev/null \
          || echo "ComfyUI（''${port}）が応答しませんでした（続けます）" >&2
      done
    }

    # LoRA学習（~/ai/scripts/lora-train）はGPUを使うunitとConflicts=で排他にしている。
    # ここで起動すると学習が止まるので、学習中は明示的に止めるまで切り替えさせない。
    guard_training() {
      if systemctl --user is-active --quiet 'lora-train-*.service'; then
        echo "LoRA学習が実行中です。止める場合は lora-train stop <name>" >&2
        systemctl --user list-units --no-legend 'lora-train-*.service' >&2
        exit 1
      fi
    }

    case "''${1:-}" in
      split)
        guard_training
        if systemctl --user is-active --quiet qwen38-dual.service; then
          unload_models
          systemctl --user stop qwen38-dual.service
        fi
        systemctl --user start comfyui.service ${comfyGpu1} qwen38.service
        # 2 つの ComfyUI が RAM に持っている重み（H3 Image のテキストエンコーダーなど）を降ろし、Qwen の RAM を空ける
        free_comfy
        ;;
      image-dual)
        guard_training
        if systemctl --user is-active --quiet qwen38-dual.service; then
          unload_models
          systemctl --user stop qwen38-dual.service
        fi
        systemctl --user start comfyui.service ${comfyGpu1} qwen38.service
        # 2 つ目の ComfyUI が GPU 1 に載せているモデルも降ろさせる（H3 Image のテキストエンコーダーの計算とぶつからないように）
        free_comfy ${comfyGpu1Port}
        unload_models_wait || exit 1
        ;;
      llm-dual)
        guard_training
        unload_models
        # qwen38-dual.service は Conflicts= で comfyui・${comfyGpu1}・qwen38 を止める。
        # ${comfyGpu1} は、Conflicts= を書き直す前の qwen38-dual.service（install-qwen38-ubuntu.sh の流し直しの前）でも止まるように、先に止める
        systemctl --user stop ${comfyGpu1} || true
        systemctl --user start qwen38-dual.service
        ;;
      applio)
        guard_training
        systemctl --user start applio.service
        ;;
      stop)
        systemctl --user stop qwen38-dual.service qwen38.service comfyui.service ${comfyGpu1} applio.service
        ;;
      status)
        systemctl --user --no-pager --full status comfyui.service ${comfyGpu1} qwen38.service qwen38-dual.service applio.service 'lora-train-*.service' || true
        nvidia-smi --query-gpu=index,name,memory.used,memory.total,temperature.gpu,power.draw --format=csv || true
        ;;
      *) usage ;;
    esac
  '';
in
{
  chibiham.ubuntu = {
    # 要確認(本人): このマシン専用のVaultを作る（chibihamuntu と同じアイテム名: CIVITAI_TOKEN、R2_CHIBIHAM_AI）。
    # hosts/ubuntu/dekahamuntu.env の OP_VAULT と揃える
    opVault = "dekahamuntu";
    aiMode = ai-mode;
  };
}
