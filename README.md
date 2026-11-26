# EstencelSessionFixMod
License: NYSL <http://www.kmonos.net/nysl>

- 3人以上でのプレイ中にロード(全滅・暖炉転送など)を挟むとプレイヤーが弾かれる不具合を回避するMod
- 導入はホストのみでok

---

## 導入手順

### 1. UE4SSの導入
1. "UE4SS-RE/RE-UE4SS"リポジトリから最新版を入手
    - 動作確認済: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v4.0.0
        - ページ下部`Assets`内: `UE4SS_v4.0.0.zip`
2. zipの中身を`Estencel\Binaries\Win64\`に展開
    - ゲームフォルダはsteamで`Estencel`->`プロパティ`->`インストール済みファイル`から飛べる
    - `Win64`下に`dwmapi.dll`, `ue4ss`フォルダが展開されていればok

### 2. Mod導入
1. 本ページ上部の`<>Code`->`Download ZIP`
2. `EstencelSessionFix`フォルダを`ue4ss\Mods\`にコピー

---

## 削除手順
それぞれ導入したものを削除するだけでok (Steamのプロセスを終了していないと削除できないかもしれない)<br>
**ゲームのアンインストール後も残ることがあるので要確認(手動削除してください)**
- UE4SS+Mod: `dwmapi.dll`, `ue4ss` を削除
- Mod単体: `Mods\EstencelSessionFix` フォルダのみ削除

---

## 使用方法
- 特に何もしなくても自動で動作します
- ロード中誰か落ちるなどした際にゲームが始まらなければF8またはOK(パッドAボタン)2回押下で揃っている人のみで強制開始できます

---

## 設定変更
`scripts\main.lua` の先頭にある `CFG` の値で設定を変更可能

- `T_CLOSE`: 受付を自動で締め切るまでの秒数
- `T_START`: 自動で強制開始するまでの秒数
- `OK_WINDOW`: OK 2回押しの受付時間(秒)
- `FORCE_KEY`: `Key.F8` 強制開始キー