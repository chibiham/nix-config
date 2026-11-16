# dekahamuntu固有のHome Manager設定
# AMD Ryzen / RTX 5060 Ti 16GB ×2（Blackwell、NVLinkなし）/ DDR5 64GB / Ubuntu 24.04
#
# llama.cppのCUDAの世代（12.0）は flake.nix の mkLinuxHome の cudaCapabilities で指定する。
# スクリプト側のホストの設定は hosts/ubuntu/dekahamuntu.env。
{ pkgs, ... }:

let
  # GPU 0 = ComfyUI、GPU 1 = Qwen（qwen38.service）を既定にし、
  # 必要なときだけ2枚を束ねたQwen（qwen38-dual.service）に切り替える。
  # unitのGPUの割り当てと Conflicts= は scripts/install-*-ubuntu.sh が hosts/ubuntu/dekahamuntu.env から書く。
  ai-mode = pkgs.writeShellScriptBin "ai-mode" ''
    set -euo pipefail

    usage() {
      cat >&2 <<'EOF'
    usage: ai-mode {split|llm-dual|applio|stop|status}
      split     GPU 0 = ComfyUI、GPU 1 = Qwen（既定。再起動後もこの形）
      llm-dual  ComfyUIとQwen（1枚）を止め、2枚を束ねたQwenを起動
      applio    GPU 0 でApplioを起動（ComfyUIは止まる。GPU 1 のQwenはそのまま）
      stop      すべて停止（LoRA学習は止めない）
      status    各サービスと学習の状態
    EOF
      exit 2
    }

    # 束ねたQwenのロード済みモデルを下ろしてから止める（VRAMを早く空ける）
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
        systemctl --user start comfyui.service qwen38.service
        ;;
      llm-dual)
        guard_training
        unload_models
        # qwen38-dual.service は Conflicts= で comfyui・qwen38 を止める
        systemctl --user start qwen38-dual.service
        ;;
      applio)
        guard_training
        systemctl --user start applio.service
        ;;
      stop)
        systemctl --user stop qwen38-dual.service qwen38.service comfyui.service applio.service
        ;;
      status)
        systemctl --user --no-pager --full status comfyui.service qwen38.service qwen38-dual.service applio.service 'lora-train-*.service' || true
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
