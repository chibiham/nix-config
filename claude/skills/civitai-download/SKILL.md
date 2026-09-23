---
name: civitai-download
description: Civitai（civitai.com）のモデル・LoRA・VAE・embedding等をダウンロードしてComfyUIのmodelsディレクトリへ配置する。ユーザーがCivitaiのURLやモデルIDを示してダウンロード・導入・追加を頼んだときに使う。
---

# Civitaiモデルのダウンロード

`civitai-download` コマンド（nix-configの `home/linux.nix` が配布）を使う。
認証は `CIVITAI_TOKEN`。コマンドが環境変数か `~/.secrets/.env.secrets` から自分で読むので、
**トークンを表示・echo・引数渡ししないこと**。

## 手順

1. まず `--dry-run` で解決結果を確認する:
   ```bash
   civitai-download --dry-run '<URL または modelVersionId>'
   ```
   モデル名・種別（`type`）・`baseModel`・バージョン・保存先（`selected.dest`）・ファイル一覧が返る。
2. 次のときはダウンロード前にユーザーに確認する:
   - 複数のファイル（fp16/fp32、pruned等）があって、どれを取得するか明らかでないとき（`--file <name>` で指定）
   - 種別の保存先が自動で決まらずエラーになったとき（`--dir <path>` で指定）
3. ダウンロードする:
   ```bash
   civitai-download '<URL>'            # 必要なら --file / --dir
   ```
   数GBのcheckpointは時間がかかるので、Bashの `run_in_background` で実行する。
   中断しても同じコマンドを再実行すれば `.part` から再開し、完了後にSHA256を検証する。
4. 完了したら、保存先・`baseModel`・`trainedWords`（LoRAのトリガーワード）をユーザーに伝える。

## 保存先

`$COMFY_DIR`（既定は `~/ComfyUI`）の `models/` 以下で、種別ごとに次のディレクトリへ保存する。

| Civitaiの種別 | 保存先 |
|---|---|
| Checkpoint | checkpoints |
| LORA / LoCon / DoRA | loras |
| TextualInversion | embeddings |
| VAE | vae |
| Controlnet | controlnet |
| Upscaler | upscale_models |

ComfyUIを再起動しなくても、ノードのモデル一覧を更新すれば新しいモデルが表示される。

## エラー時

- `CIVITAI_TOKEN が未設定`: 1Passwordの `chibihamuntu` Vaultに `CIVITAI_TOKEN`（credentialフィールド）を作成し、
  `update-secrets` を実行するようユーザーに依頼する。
- 401/403: トークンの失効、または早期アクセス（Early Access）制限の可能性がある。
