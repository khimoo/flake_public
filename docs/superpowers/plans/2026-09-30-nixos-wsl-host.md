# nixos-wsl ホスト追加 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 会社 PC の NixOS-WSL を `nixosConfigurations.nixos-wsl` として追加し、秘密情報と外部への接続経路を持たない CLI 専用ホストにする。

**Architecture:** 既存ホストの共通設定を `modules/nixos/base.nix` に切り出し、desktop 向けは `common.nix` に残す。WSL ホストは NixOS-WSL のモジュールと `base.nix` だけを読み、home は agents-private 用の設定（`profiles/home/pomu-agents.nix`）だけを共有する。前半（パート A）は今の 25.11 の lock で行う純粋な分割、後半（パート B）は repo 全体を 26.05 に上げたあとに行う WSL ホストの追加。

**Tech Stack:** Nix flakes、NixOS modules、Home Manager、NixOS-WSL（release-26.05）、`tests/default.nix` の評価時 assert、`scripts/check.sh`

**Spec:** [docs/architecture/wsl.md](../../architecture/wsl.md)

この計画ファイルは作業用で、コミットしない。一回きりの手順は repo の文書に残さず、コミットメッセージに残す方針のため。パート B まで終わったら削除する。

## Global Constraints

- `nixos-rebuild`、`home-manager switch` など世代を切り替えるコマンドは実行しない（AGENTS.md）。`nix eval`、`nix build`、`nix flake check` は実行してよい。
- 重い評価とビルドは desktop（nixos-desktop）で行う。spin713 では `bash scripts/check.sh` を実行しない。
- パート A は `flake.lock` を変えない。すべての nix コマンドに `--no-update-lock-file` を付ける。
- パート B の前提は nixpkgs と home-manager が 26.05（`nixos-26.05`、`release-26.05`）であること。NixOS-WSL の input は `github:nix-community/NixOS-WSL/release-26.05`、`inputs.nixpkgs.follows = "nixpkgs"`。
- WSL ホストの値: ホスト名 `nixos-wsl`、ユーザー `nixos`（`isAdmin = true`）、`stateVersion = "26.05"`、`timezone = "Asia/Tokyo"`、`system = "x86_64-linux"`。
- WSL には age 鍵、secret、`lanSsh`、ssh.nix、tailscale.nix、remote-builders.nix を入れない。git の identity は repo に書かない（null のまま）。
- deploy key の別名: `Host github-agents-private`、`HostName github.com`、`User git`、`IdentityFile ~/.ssh/id_agents_private`、`IdentitiesOnly yes`。置き場は NixOS の `programs.ssh.extraConfig`。
- 作業用のファイル（drvPath の記録など）は `.git/nixos-wsl-plan/` に置く。作業ツリーに入らず、セッションをまたいでも残る。
- コミットメッセージは既存の履歴に合わせて日本語の Conventional Commits にする。コミット前の校正フックが案を出したら、壊れた箇所だけ直して採る。
- 新しく書く日本語の文書（`docs/howtouse/wsl.md`）は gemini-proofread に通す。既存の文書の数行の修正は通さない（ファイル全体が書き換わるため）。
- コードにコメントを書くときは writing-code-comments skill に従う。

## Review Focus

- 会社用の SSH 鍵を `~/.ssh/config` の `Host *` に書いた状態で agents-private を clone する：deploy key だけが使われるべきだが、repo からは強制できない。Task 3 で別名の区切りに `IdentitiesOnly yes` があることを assert し、Task 5 の howtouse に `ssh -G` の確認手順を書く。
- age 鍵がない状態での初回 switch：activation が止まらないこと。Task 3 で `secrets` と `privateRepos` の activation がないことを assert する。
- 分割で desktop と spin713 の設定が落ちる（codex-astra の指摘した adb など）：Task 1 と Task 2 で toplevel の drvPath を前後比較する。
- 会社の GitHub への SSH 接続に deploy key が混ざる：Task 3 で `/etc/ssh/ssh_config` に `Host github.com` がないことを assert する。
- 初回 switch の直後、WSL を再起動するまではホスト名が `nixos` のまま：`--flake .` だと `nixosConfigurations.nixos` を探して失敗する。Task 5 の howtouse では常に `#nixos-wsl` を明示する。

---

## パート A：今の 25.11 の lock で行う分割

### Task 1: NixOS 側の共通設定を `base.nix` に切り出す

**Files:**
- Create: `modules/nixos/base.nix`
- Create: `modules/nixos/adb.nix`
- Modify: `modules/nixos/common.nix`（全体）
- Modify: `modules/nixos/networking.nix:2-3`（`networking.hostName` を削除）
- Modify: `modules/nixos/nix-settings.nix:30-37`（gparted、gsconnect、`programs.adb` を削除）
- Modify: `modules/nixos/desktop.nix`（gparted と gsconnect を追加）
- Modify: `docs/howtouse/codex-subagents.md:10`

**Interfaces:**
- Consumes: `specialArgs.settings.hostname`、`specialArgs.settings.stateVersion`（`lib/configurations.nix` の `mkSystem` が渡す）
- Produces: `modules/nixos/base.nix`。どのホストでも要る設定だけを持つ NixOS モジュールで、Task 3 の `hosts/nixos-wsl/default.nix` が import する。

- [ ] **Step 1: 分割前の drvPath を記録する**

```bash
cd ~/sagyo/flake_public
mkdir -p .git/nixos-wsl-plan
for h in nixos-desktop nixos-spin713; do
  nix eval --no-update-lock-file --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" \
    > ".git/nixos-wsl-plan/before-$h"
  # drvPath が変わったときに中身を比べるため、分割前の system-path を GC root 付きで残す。
  nix build --no-update-lock-file --out-link ".git/nixos-wsl-plan/before-path-$h" \
    ".#nixosConfigurations.$h.config.system.path"
done
cat .git/nixos-wsl-plan/before-nixos-*
```

Expected: `/nix/store/...-nixos-system-nixos-desktop-....drv` と spin713 の同様のパスが 1 行ずつ出て、`.git/nixos-wsl-plan/before-path-*` の 2 つのリンクができる。mutter のパッチ版の置換で IFD が走るので、store になければ数分かかる。

- [ ] **Step 2: `modules/nixos/base.nix` を作る**

```nix
# どのホストでも要る設定。desktop 向けの残りは common.nix が持ち、nixos-wsl はこれだけを読む
# （docs/architecture/wsl.md）。
{ specialArgs, ... }: {
  imports = [
    ./locale.nix
    ./users.nix
    ./nix-settings.nix
    ./codex.nix
    ./agent-instructions.nix
    ./claude-managed-settings.nix
    ./permit-insecure.nix
  ];

  networking.hostName = specialArgs.settings.hostname;
  system.stateVersion = specialArgs.settings.stateVersion;
}
```

- [ ] **Step 3: `modules/nixos/adb.nix` を作る**

```nix
# Android 端末を USB で扱う。WSL では使わないので、base.nix ではなく common.nix から読む。
{ ... }: {
  programs.adb.enable = true;
}
```

- [ ] **Step 4: `modules/nixos/common.nix` を書き換える**

```nix
# 共通ホスト設定
# base.nix（どのホストでも要る設定）に、desktop 向けのサブモジュールを足す
# 各サブモジュールは単一の責務を持つ（機能的凝集を目指す）

{ ... }: {
  imports = [
    ./base.nix
    ./boot.nix
    ./networking.nix
    ./desktop.nix
    ./adb.nix
    ./printing.nix
    ./ssh.nix
    ./tailscale.nix
    ./remote-builders.nix
    ./bluetooth.nix
    ./libvirt.nix
    ./audio.nix
    ./sns-block.nix
    ./gnome-transparent-fullscreen.nix
  ];
}
```

- [ ] **Step 5: `modules/nixos/networking.nix` から `networking.hostName` を消す**

変更後の先頭 3 行:

```nix
# ネットワーク・ファイアウォール設定
{ ... }: {
  networking.networkmanager.enable = true;
```

- [ ] **Step 6: `modules/nixos/nix-settings.nix` から GUI と adb を外す**

`# システムパッケージ` 以降を次に置き換える（ファイル末尾まで）:

```nix
  # システムパッケージ
  environment.systemPackages = [
    inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager # manageHome = falseの人もhome-manager使えるようにしてる
  ];
}
```

- [ ] **Step 7: `modules/nixos/desktop.nix` に gparted と gsconnect を移す**

```nix
# デスクトップ環境（GNOME/GDM）とキーマップ設定
{ pkgs, specialArgs, ... }: {
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = specialArgs.settings.keymap;
    variant = "";
  };

  environment.systemPackages = with pkgs; [
    gparted
    gnomeExtensions.gsconnect
  ];
}
```

- [ ] **Step 8: 分割後の drvPath を記録して比べる**

Git flake は追跡されていないファイルを読まないので、新しいファイルを先に intent-to-add で登録する（`docs/howtouse/validation.md`）。

```bash
cd ~/sagyo/flake_public
git add -N modules/nixos/base.nix modules/nixos/adb.nix
for h in nixos-desktop nixos-spin713; do
  nix eval --no-update-lock-file --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" \
    > ".git/nixos-wsl-plan/after1-$h"
  cmp ".git/nixos-wsl-plan/before-$h" ".git/nixos-wsl-plan/after1-$h" && echo "$h: identical"
done
```

Expected: 両方 `identical`。違いが出たホストは Step 9 に進む。

- [ ] **Step 9: drvPath が違ったら、system-path の中身と残りの差分を確かめる**

system-path は `buildEnv` の `ignoreCollisions = true` で作られ、同じファイルを持つパッケージがあると並び順で先のものが残る（nixpkgs の `nixos/modules/config/system-path.nix`）。そのため「差分が並び順だけ」では挙動が同じとは言えない。system-path の中のリンクがすべて同じであることを直接確かめる。

```bash
cd ~/sagyo/flake_public
h=nixos-desktop   # 違いが出たホスト
nix build --no-update-lock-file --out-link ".git/nixos-wsl-plan/after1-path-$h" \
  ".#nixosConfigurations.$h.config.system.path"
diff <(cd -P ".git/nixos-wsl-plan/before-path-$h" && find . -printf '%y %p %l\n' | sort) \
     <(cd -P ".git/nixos-wsl-plan/after1-path-$h" && find . -printf '%y %p %l\n' | sort) \
  && echo "$h: system-path identical"
nix run --no-update-lock-file --inputs-from . nixpkgs#nix-diff -- \
  "$(cat .git/nixos-wsl-plan/before-$h)" "$(cat .git/nixos-wsl-plan/after1-$h)"
```

Expected: `system-path identical` が出て、`nix-diff` の差分は system-path の `paths` の並び順と、それを参照する上位の derivation だけ。system-path のリンクに違いがあるか、`programs.adb` 由来の udev ルールやグループ、ホスト名など system-path 以外に差分があれば分割の誤りなので、Step 2〜7 を見直す。

- [ ] **Step 10: `docs/howtouse/codex-subagents.md` の import 元を直す**

10 行目:

```markdown
`/etc/codex/config.toml` を生成する。`modules/nixos/base.nix` から import 済みなので
```

- [ ] **Step 11: 文書を検証してコミットする**

```bash
cd ~/sagyo/flake_public
python3 scripts/check-docs.py . && git diff --check
git add modules/nixos/base.nix modules/nixos/adb.nix modules/nixos/common.nix \
  modules/nixos/networking.nix modules/nixos/nix-settings.nix modules/nixos/desktop.nix \
  docs/howtouse/codex-subagents.md
git commit -m "refactor: どのホストでも要る NixOS 設定を base.nix に切り出す"
```

コミット本文には、Step 8 の結果（同一だったか、並び順だけの差分だったか）を書く。

### Task 2: agents-private 用の home 設定を `pomu-agents.nix` に切り出す

**Files:**
- Create: `profiles/home/pomu-agents.nix`
- Modify: `profiles/home/pomu-workstation.nix`（全体）

**Interfaces:**
- Consumes: `local.profile.agentConfigRoot`、`local.profile.agentProfiles`（`modules/home-manager/profile.nix`）、`local.agentCompression`（`modules/home-manager/dev/agent-compression.nix`）
- Produces: `profiles/home/pomu-agents.nix`。Task 3 の `hosts/nixos-wsl/home.nix` が import する。`agentConfigRepo` は含まない。

- [ ] **Step 1: `profiles/home/pomu-agents.nix` を作る**

```nix
# agents-private（Claude Code と Codex の設定 repo）を使うための設定。clone URL（agentConfigRepo）は
# ここに置かない。置くと sops で id_github を復号する処理が加わり、age 鍵を持たない nixos-wsl の
# activation が止まる（docs/architecture/wsl.md）。
{ config, ... }:
{
  local.profile = {
    agentConfigRoot = "${config.home.homeDirectory}/sagyo/agents-private";
    agentProfiles = {
      claude = [
        "opus"
        "fable"
      ];
      codex = [ "astra" ];
    };
  };

  # 日本語のセッションを既定にする。英語でコメントや文書を書くときだけ /caveman で切り替える。
  local.agentCompression = {
    caveman = "off";
    genshijin = "normal";
  };
}
```

- [ ] **Step 2: `profiles/home/pomu-workstation.nix` から移した分を消す**

```nix
{ config, ... }:
let
  work = "${config.home.homeDirectory}/sagyo";
in
{
  imports = [
    ./pomu.nix
    ./pomu-agents.nix
  ];
  local.profile = {
    features = {
      gui = true;
      gnome = true;
      ime = true;
      audio = true;
      referenceSync = true;
      zettelkastenSync = true;
      obsidian = true;
    };
    lanSsh = true;
    zettelkastenRoot = "${work}/zettelkasten";
    zettelkastenRepoUrl = "git@github.com:khimoo/zettelkasten.git";
    agentConfigRepo = "git@github.com:khimoo/agents-private.git";
    vaultSkeletonRepo = "${work}/zettelkasten-workflow";
    vaultSkeletonRepoUrl = "git@github.com:khimoo/zettelkasten-workflow.git";
    llmWikisRoot = "${work}/llm-wikis";
    llmWikisRepoUrl = "git@github.com:khimoo/llm-wikis.git";
  };
}
```

- [ ] **Step 3: drvPath が Task 1 の後と同じか比べる**

```bash
cd ~/sagyo/flake_public
git add -N profiles/home/pomu-agents.nix   # Git flake は追跡されていないファイルを読まない
for h in nixos-desktop nixos-spin713; do
  nix eval --no-update-lock-file --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" \
    > ".git/nixos-wsl-plan/after2-$h"
  cmp ".git/nixos-wsl-plan/after1-$h" ".git/nixos-wsl-plan/after2-$h" && echo "$h: identical"
done
```

Expected: 両方 `identical`。値を別ファイルに移しただけなので、並び順の差も出ないはず。違いが出たら Task 1 Step 9 と同じ `nix-diff` で原因を特定する。

- [ ] **Step 4: パート A 全体を検証する**

共有のモジュール構成に触れたので、AGENTS.md に従い全体の検証を desktop で行う。

```bash
cd ~/sagyo/flake_public
bash scripts/check.sh
```

Expected: 最後まで失敗せずに終わる（`git diff --check` まで）。

- [ ] **Step 5: コミットする**

```bash
cd ~/sagyo/flake_public
git add profiles/home/pomu-agents.nix profiles/home/pomu-workstation.nix
git commit -m "refactor: agents-private 用の home 設定を pomu-agents.nix に切り出す"
```

---

## パート B：26.05 に上げたあとに行う WSL ホストの追加

### パート B の開始条件

repo 全体を 26.05 に上げる作業（別の設計と計画）が main に入っていること。次で確かめる。

```bash
cd ~/sagyo/flake_public
nix eval --no-update-lock-file --raw .#nixosConfigurations.nixos-desktop.pkgs.lib.trivial.release; echo
grep -n 'home-manager/release-26.05' flake.nix
```

Expected: `26.05` と、`release-26.05` を含む 1 行。どちらかが違えばパート B に進まない。

### Task 3: `nixos-wsl` ホストを足し、会社 PC に閉じる条件をテストで固定する

**Files:**
- Modify: `tests/default.nix`（let に `wsl` の束縛、`contracts` に assert）
- Modify: `flake.nix`（input に `nixos-wsl`、`nixosConfigurations` に `nixos-wsl`）
- Modify: `flake.lock`（`nixos-wsl` とその依存の追加だけ）
- Create: `hosts/nixos-wsl/default.nix`
- Create: `hosts/nixos-wsl/home.nix`

**Interfaces:**
- Consumes: `modules/nixos/base.nix`（Task 1）、`profiles/home/pomu-agents.nix`（Task 2）、`inputs.nixos-wsl.nixosModules.default`、`specialArgs.settings.primaryUser`
- Produces: `inputs.self.nixosConfigurations.nixos-wsl`。Task 5 の文書はこのホスト名と、`github-agents-private`、`~/.ssh/id_agents_private` の名前を使う。

- [ ] **Step 1: 失敗するテストを書く**

`tests/default.nix` の `users = fixture.config.home-manager.users;` の次の行に足す:

```nix
  # 会社 PC に閉じる条件は、架空のホストではなく実際の nixos-wsl で確かめる（docs/architecture/wsl.md）。
  wsl = inputs.self.nixosConfigurations.nixos-wsl.config;
  wslUser = wsl.home-manager.users.nixos;
  wslSshConfig = wsl.environment.etc."ssh/ssh_config".text;
  # deploy key は、この区切りの中にだけ現れなければならない。別の区切りや Host * に付くと、
  # 会社の GitHub への接続にも deploy key が使われる。
  wslDeployKeyBlock = ''
    Host github-agents-private
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_agents_private
      IdentitiesOnly yes
  '';
  countOf = needle: haystack: builtins.length (lib.splitString needle haystack) - 1;
```

`contracts` の `assert allAssertions home;` の次の行に足す:

```nix
      assert wsl.wsl.enable;
      assert wsl.wsl.defaultUser == "nixos";
      assert !wsl.services.openssh.enable;
      assert !wsl.services.tailscale.enable;
      assert wsl.nix.buildMachines == [ ];
      assert lib.hasInfix wslDeployKeyBlock wslSshConfig;
      assert countOf "id_agents_private" wslSshConfig == 1;
      assert countOf "IdentityFile" wslSshConfig == 1;
      assert !(lib.hasInfix "Host github.com" wslSshConfig);
      assert wsl.local.claudeManagedSettings == "/home/nixos/sagyo/agents-private/claude/managed-settings.json";
      assert wslUser.local.profile.gitUsername == null;
      assert wslUser.local.profile.gitUserEmail == null;
      assert !wslUser.local.profile.lanSsh;
      assert !(lib.any (enabled: enabled) (lib.attrValues wslUser.local.profile.features));
      assert wslUser.local.profile.privateRepos == [ ];
      assert wslUser.local.profile.sshKeys == [ ];
      assert wslUser.local.profile.secrets == [ ];
      assert !(wslUser.home.activation ? secrets);
      assert !(wslUser.home.activation ? privateRepos);
      assert wslUser.local.profile.agentConfigRoot == "/home/nixos/sagyo/agents-private";
      assert hasLauncher wslUser "codex-astra";
```

- [ ] **Step 2: テストが失敗することを確かめる**

```bash
cd ~/sagyo/flake_public
nix build --no-link --no-update-lock-file .#checks.x86_64-linux.module-contracts
```

Expected: FAIL。`attribute 'nixos-wsl' missing` を含むエラー。

- [ ] **Step 3: flake input を足して lock に加える**

`flake.nix` の `inputs` の `rnote.url = ...;` の前に足す:

```nix
    # WSL ホストの OS 側（wsl.conf、既定ユーザー、ブートローダーの代わり）。ブランチは nixpkgs の
    # リリースに合わせる（docs/architecture/wsl.md）。
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

```bash
cd ~/sagyo/flake_public
cp flake.lock .git/nixos-wsl-plan/flake.lock.before
nix flake lock
python3 - <<'EOF'
import json
before = json.load(open(".git/nixos-wsl-plan/flake.lock.before"))["nodes"]
after = json.load(open("flake.lock"))["nodes"]
key = lambda node: (node.get("locked"), node.get("inputs"), node.get("original"))
changed = [n for n in before if n != "root" and key(after.get(n, {})) != key(before[n])]
root_before, root_after = before["root"]["inputs"], after["root"]["inputs"]
print("changed existing nodes:", changed)
print("root inputs added:", sorted(set(root_after) - set(root_before)))
print("root inputs changed:", [k for k in root_before if root_after.get(k) != root_before[k]])
EOF
```

Expected: `changed existing nodes: []`、`root inputs added: ['nixos-wsl']`、`root inputs changed: []`。既存のノードが変わっていたら、`git checkout flake.lock` で戻して原因を調べる。

- [ ] **Step 4: `hosts/nixos-wsl/default.nix` を作る**

```nix
# 会社 PC の NixOS-WSL。CLI だけのホストにし、秘密情報と外部への接続経路を持たせない
# （docs/architecture/wsl.md）。
{ config, inputs, settings, ... }:
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ../../modules/nixos/base.nix
  ];

  wsl.enable = true;
  wsl.defaultUser = settings.primaryUser;

  local.claudeManagedSettings = "${
    config.home-manager.users.${settings.primaryUser}.local.profile.agentConfigRoot
  }/claude/managed-settings.json";

  # deploy key を github.com に付けると、会社のアカウントでの SSH 接続も deploy key で認証される。
  # ~/.ssh/config は会社用の設定を手で書けるように Home Manager で管理しない。
  programs.ssh.extraConfig = ''
    Host github-agents-private
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_agents_private
      IdentitiesOnly yes
  '';
}
```

- [ ] **Step 5: `hosts/nixos-wsl/home.nix` を作る**

```nix
# pomu.nix（khimoo の identity と Gemini の secret）は読まない（docs/architecture/wsl.md）。
{ ... }:
{
  imports = [ ../../profiles/home/pomu-agents.nix ];
}
```

- [ ] **Step 6: `flake.nix` の `nixosConfigurations` に足す**

`nixos-desktop = mkSystem { ... };` の後に足す:

```nix
        nixos-wsl = mkSystem {
          hostname = "nixos-wsl";
          system = "x86_64-linux";
          users = [
            {
              username = "nixos";
              isAdmin = true;
              homeFile = ./hosts/nixos-wsl/home.nix;
            }
          ];
          timezone = "Asia/Tokyo";
          stateVersion = "26.05";
        };
```

- [ ] **Step 7: テストが通ることを確かめる**

```bash
cd ~/sagyo/flake_public
git add hosts/nixos-wsl   # flake は git に追跡されたファイルしか見ない
nix build --no-link --no-update-lock-file .#checks.x86_64-linux.module-contracts
```

Expected: PASS（出力なしで終了コード 0）。失敗したら、エラーの assert がどの条件かを見て、Step 4〜6 のどこが原因かを直す。

- [ ] **Step 8: WSL の toplevel を評価し、ビルドする**

```bash
cd ~/sagyo/flake_public
nix eval --no-update-lock-file --raw .#nixosConfigurations.nixos-wsl.config.system.build.toplevel.drvPath; echo
nix build --no-link --no-update-lock-file .#nixosConfigurations.nixos-wsl.config.system.build.toplevel
```

Expected: drvPath が 1 行出て、ビルドが成功する。評価時の警告（`evaluation warning:`）が出たら内容を記録し、WSL 固有の設定に関するものなら直す。

- [ ] **Step 9: コミットする**

```bash
cd ~/sagyo/flake_public
git add flake.nix flake.lock hosts/nixos-wsl tests/default.nix
git commit -m "feat: 会社 PC の NixOS-WSL を nixos-wsl ホストとして追加する"
```

### Task 4: standalone の `pomu-wsl` を消し、既存の文書を直す

**Files:**
- Modify: `flake.nix`（`homeConfigurations."pomu-wsl"` を削除）
- Modify: `README.md:3`、`README.md:20-22`、`README.md:38`
- Modify: `docs/howtouse/README.md:29-30`
- Modify: `docs/howtouse/codex-subagents.md:13`
- Modify: `docs/howtouse/agent-config.md:142`
- Modify: `docs/howtouse/machine-ssh.md:80-81`
- Modify: `docs/howtouse/private-repo-clone.md:5-6`
- Modify: `docs/howtouse/validation.md:15`
- Modify: `docs/architecture/private-repo-clone.md:15`、`docs/architecture/private-repo-clone.md:24`、`docs/architecture/private-repo-clone.md:117`、`docs/architecture/private-repo-clone.md:189`
- Modify: `docs/architecture/codex-subagents.md:59`
- Modify: `docs/architecture/comma.md:12`
- Modify: `docs/architecture/unstable-packages.md:119`
- Modify: `docs/architecture/tailscale.md:8`

**Interfaces:**
- Consumes: `nixosConfigurations.nixos-wsl`（Task 3）
- Produces: なし

- [ ] **Step 1: `flake.nix` から `pomu-wsl` を消す**

`homeConfigurations` の次のブロックを丸ごと削除する:

```nix
        "pomu-wsl" = mkHome {
          username = "pomu";
          system = "x86_64-linux";
          stateVersion = "25.05";
          homeFile = ./profiles/home/pomu.nix;
        };
```

確認:

```bash
cd ~/sagyo/flake_public
nix eval --no-update-lock-file .#homeConfigurations --apply builtins.attrNames
```

Expected: `[ "pomu-macos" "pomu-nixos" ]`

- [ ] **Step 2: `README.md` を直す**

3 行目:

```markdown
個人用のNixOS 2台と会社PCのNixOS-WSL、macOS向けHome Manager環境を管理するリポジトリです。
```

「対応範囲」の最初の 2 項目（NixOS と Home Manager の行）を、次の 3 項目に置き換える。3 項目目の RustOwl の行以降は残す。

```markdown
- NixOS: `nixos-desktop`, `nixos-spin713`（x86_64 Linux）。個人プロファイルがGUI・音楽制作・vault同期を選択。
- NixOS-WSL: `nixos-wsl`（x86_64 Linux CLI、会社PC）。秘密情報と外部への接続経路を持たない。[手順](docs/howtouse/wsl.md) · [設計判断](docs/architecture/wsl.md)
- Home Manager: `pomu-macos`（aarch64 Darwin CLI）、`pomu-nixos`（x86_64 Linux GUI・音楽制作）。
```

「セットアップ・適用」のコードブロックの最後の 2 行:

```sh
# または standalone Home Manager
home-manager switch --flake .#pomu-macos
```

- [ ] **Step 3: `docs/howtouse/README.md` の 2 行を直す**

29 行目の `新環境（NixOS/WSL/macOS）` を `新環境（NixOS/macOS。会社PCの nixos-wsl は除く）` に、30 行目の `NixOS 以外（WSL/macOS）で` を `NixOS 以外（macOS）で` に置き換える。

- [ ] **Step 4: howtouse の各文書を直す**

`docs/howtouse/codex-subagents.md` 13 行目:

```markdown
## NixOS 以外（macOS）の場合
```

`docs/howtouse/agent-config.md` 142 行目:

```markdown
対象は NixOS ホスト（nixos-wsl を含む）だけで、standalone home-manager（macOS）には入らない。
```

`docs/howtouse/machine-ssh.md` 80〜81 行目:

```markdown
- 対象は ssh.nix を読む NixOS ホストのみ。standalone home-manager（macOS）と、
  会社PCの nixos-wsl（[wsl.md](./wsl.md)）は LAN の一員とみなさず `id_lan` を配らない
```

`docs/howtouse/private-repo-clone.md` 5〜6 行目:

```markdown
Claude 設定・Obsidian workflow）も switch が clone する。NixOS でも 非 NixOS
（macOS）でも同じ経路（home-manager の `home.activation`）で動く。会社PCの nixos-wsl は
age 鍵を置かないので、この仕組みを使わない（[wsl.md](./wsl.md)）。
```

`docs/howtouse/validation.md` 15 行目:

```markdown
2. 全NixOSホストの `system.build.toplevel.drvPath` を明示評価してから、`nix flake check --no-build --no-update-lock-file` で全NixOSホスト・native packages・devShells・checksを評価。
```

- [ ] **Step 5: architecture の各文書を直す**

`docs/architecture/private-repo-clone.md` 15 行目の `非 NixOS（WSL / macOS）も含む。` を `非 NixOS（macOS）も含む（会社PCの nixos-wsl は age 鍵を置かないので対象外。[wsl.md](./wsl.md)）。` に、24 行目の `NixOS 専用になり、WSL / macOS を切り捨てる` を `NixOS 専用になり、macOS を切り捨てる` に置き換える。

同じファイルの 117 行目の `` NixOS ホストは `id_lan` のために `sshKeys` が常に非空だからである。 `` を `` `lanSsh` を有効にしているユーザー（desktop と spin713 の pomu）は、`id_lan` のために `sshKeys` が常に非空だからである。`` に、189 行目の `` - NixOS ホストは `sshKeys` が常に非空なので、 `` を `` - `lanSsh` を有効にしているユーザー（desktop と spin713 の pomu）は `sshKeys` が常に非空なので、`` に置き換える。nixos-wsl の `nixos` ユーザーは `sshKeys` が空なので、「NixOS ホストは常に非空」は成り立たなくなる。

`docs/architecture/codex-subagents.md` 59 行目の `WSL や macOS でも効く。` を `macOS でも効く。` に置き換える。

`docs/architecture/comma.md` 12 行目の `standalone の Home Manager を使う WSL と macOS に入らない。` を `standalone の Home Manager を使う macOS に入らない。` に置き換える。

`docs/architecture/unstable-packages.md` 119 行目の `（WSL / macOS）` を `（macOS）` に置き換える。

`docs/architecture/tailscale.md` 8 行目:

```markdown
- `modules/nixos/tailscale.nix` — `common.nix` を読むホストで tailscaled を有効にする（会社PCの nixos-wsl は読まない）
```

- [ ] **Step 6: 残りの参照を探す**

```bash
cd ~/sagyo/flake_public
grep -rn -E 'pomu-wsl|WSL' --include=*.md README.md docs | grep -v -E 'docs/(architecture|howtouse)/wsl\.md|zettelkasten-vault-skeleton|docs/superpowers/'
grep -rn -E '両ホスト|2台|NixOS ホストは|全ホストで|全マシン' --include=*.md README.md docs | grep -v -E 'docs/superpowers/'
```

Expected: 出てくる行はすべて、今の構成（nixos-wsl は NixOS ホスト、standalone は macOS だけ）と矛盾しない。zettelkasten の文書にある WSL の Obsidian の記述は別の話なので対象外。二つ目の検索は、NixOS ホストの数や「全ホスト」を前提にした記述を拾う。個人用の 2 台（desktop と spin713）の話として正しい行は残し、nixos-wsl を含む全ホストの話として誤りになった行だけ直す。

- [ ] **Step 7: 検証してコミットする**

`docs/howtouse/wsl.md` はまだないので、この時点の `check-docs.py` はそのリンクで失敗する。Task 5 と同じコミットにまとめるため、ここではステージだけして Task 5 に進む。

```bash
cd ~/sagyo/flake_public
git diff --check
git add flake.nix README.md docs/howtouse/README.md docs/howtouse/codex-subagents.md \
  docs/howtouse/agent-config.md docs/howtouse/machine-ssh.md docs/howtouse/private-repo-clone.md \
  docs/howtouse/validation.md docs/architecture/private-repo-clone.md docs/architecture/codex-subagents.md \
  docs/architecture/comma.md docs/architecture/unstable-packages.md docs/architecture/tailscale.md
```

### Task 5: WSL の手順書を書き、設計文書を実装済みにする

**Files:**
- Create: `docs/howtouse/wsl.md`
- Modify: `docs/howtouse/README.md`（目次に 1 行）
- Modify: `docs/architecture/wsl.md`（冒頭、手順の記述、「移行手順」と「ドキュメントの更新計画」の節）
- Modify: `docs/architecture/README.md`（`wsl.md` の行）

**Interfaces:**
- Consumes: ホスト名 `nixos-wsl`、別名 `github-agents-private`、鍵 `~/.ssh/id_agents_private`（Task 3）
- Produces: なし

- [ ] **Step 1: NixOS-WSL の配布名と nixos-rebuild の flakes の扱いを 26.05 で確かめる**

```bash
cd ~/sagyo/flake_public
src=$(nix eval --no-update-lock-file --raw .#nixosConfigurations.nixos-wsl.pkgs.path)
grep -n 'FLAKE_FLAGS' "$src/pkgs/by-name/ni/nixos-rebuild-ng/src/nixos_rebuild/nix.py" | head -2
wsl_src=$(nix eval --impure --raw --expr "(builtins.getFlake \"git+file://$PWD\").inputs.nixos-wsl.outPath")
grep -n 'defaultName' "$wsl_src/modules/build-tarball.nix"
```

Expected: `FLAKE_FLAGS: Final = ["--extra-experimental-features", "nix-command flakes"]`（nixos-rebuild が flakes の機能を自分で有効にする）と、`oobe.defaultName = "NixOS";`（Windows 側の配布名）。違っていたら Step 2 の手順を実際の値に合わせる。

- [ ] **Step 2: `docs/howtouse/wsl.md` を書く**

````markdown
# 会社PCの NixOS-WSL（nixos-wsl）

会社の Windows PC に入れた NixOS-WSL を、この flake の `nixosConfigurations.nixos-wsl` で管理する。
このホストには秘密情報と、自宅のマシンへの接続経路を持たせない。判断の根拠は [docs/architecture/wsl.md](../architecture/wsl.md) を参照。

## 新しいPCに入れる

1. Windows 側で NixOS-WSL のイメージを入れて起動する。イメージは flake の nixpkgs と同じリリースのものを使う（26.05 なら 2605.x）。既定のユーザー `nixos` でログインした状態になる。
2. flake を GitHub から直接指定して switch する。この時点では git がないので clone しない。`nixos-rebuild` は flakes の機能を自分で有効にして nix を呼ぶので、`nix.conf` の設定は要らない。

   ```sh
   sudo nixos-rebuild switch --flake github:khimoo/flake_public#nixos-wsl
   ```

3. Windows 側の PowerShell で WSL を止めてから開き直す。ホスト名が `nixos-wsl` に変わる。

   ```powershell
   wsl --terminate NixOS
   ```

4. flake を https で clone する。この PC からは push しない。

   ```sh
   git clone https://github.com/khimoo/flake_public.git ~/sagyo/flake_public
   ```

5. agents-private を読むための deploy key を作る。

   ```sh
   ssh-keygen -t ed25519 -C nixos-wsl-agents-private -f ~/.ssh/id_agents_private
   cat ~/.ssh/id_agents_private.pub
   ```

   表示された公開鍵を、自宅のマシンから GitHub の agents-private の Settings → Deploy keys に登録する。「Allow write access」には印を付けない。

6. 使われる鍵を確かめてから、agents-private を別名で clone する。

   ```sh
   ssh -G github-agents-private | grep -E '^(hostname|user|identityfile|identitiesonly) '
   git clone git@github-agents-private:khimoo/agents-private.git ~/sagyo/agents-private
   ```

   `identityfile` の行が `~/.ssh/id_agents_private` の 1 行だけで、`identitiesonly yes` になっていればよい。

`~/.claude` などへの symlink と `/etc/claude-code/managed-settings.json` は、agents-private を clone した時点でリンク先が現れる。clone のあとに switch し直す必要はない。

## 会社の git と SSH の設定

会社の identity は `~/.gitconfig` に書く。この repo には書かない。

```sh
git config --file ~/.gitconfig user.name "<会社での名前>"
git config --file ~/.gitconfig user.email "<会社のメールアドレス>"
```

`~/.gitconfig` がない状態で `git config --global` を使うと、git は Home Manager が管理する読み取り専用の `~/.config/git/config` に書こうとして失敗する。最初は `--file ~/.gitconfig` で書く。

会社の GitHub 用の鍵は、`~/.ssh/config` の `Host github.com` の区切りに書く。

```
Host github.com
  IdentityFile ~/.ssh/id_company
  IdentitiesOnly yes
```

`Host *` に書くと、`github-agents-private` への接続でも会社用の鍵が先に試され、会社のアカウントとして認証されて agents-private の pull が失敗する。書いたあとに、上の手順 6 の `ssh -G` で agents-private 用の鍵だけが使われることを確かめる。

## 更新する

```sh
git -C ~/sagyo/flake_public pull
git -C ~/sagyo/agents-private pull
sudo nixos-rebuild switch --flake ~/sagyo/flake_public#nixos-wsl
```

`#nixos-wsl` は省略しない。手順 3 の再起動前はホスト名が `nixos` のままで、省略すると存在しない `nixosConfigurations.nixos` を探して失敗する。

flake や agents-private の変更は自宅のマシンで行って push し、この PC では pull だけする。

## 置かないもの

- age 鍵（`~/.config/sops/age/keys.txt`）：同じ鍵で、自宅のマシンに入る `lan_ssh_key` と GitHub の `git_ssh_key` まで復号できる。
- Gemini の API キー：置くと、agents-private のコミット前の校正フックが、会社のコミットメッセージを Gemini に送るようになる。キーがなければ校正は失敗し、コミットはそのまま通る。
- `khimoo` の push 権限がある資格情報：WSL のディスクは会社の管理ツールや管理者から読める。

## うまくいかないとき

agents-private の clone や pull が `Repository not found` で失敗するときは、会社用の鍵が混ざっている。手順 6 の `ssh -G` の出力に `~/.ssh/id_agents_private` 以外の `identityfile` があれば、`~/.ssh/config` の `Host *` に会社用の鍵が書かれていないかを見る。
````

- [ ] **Step 3: `docs/howtouse/wsl.md` を gemini-proofread に通す**

`rewrite.py file` は、日本語の文字の割合が 5 割未満の文書を送らない（この文書はコマンドが多く、下回る可能性が高い）。まず `rewrite.py file` を試し、`diff` が空なら `collect.py --text` と `proofread.py` の経路で送り、結果を書き戻す。

```bash
cd ~/sagyo/flake_public
python3 ~/.claude/skills/gemini-proofread/scripts/rewrite.py file docs/howtouse/wsl.md
```

校正結果の扱い（壊れた箇所だけ直す、意味がずれた箇所は原文を書き直して送り直す）は gemini-proofread skill に従う。コマンド、パス、鍵の名前、`Host` の区切りの中身が一字でも変わっていたら原文に戻す。

- [ ] **Step 4: `docs/howtouse/README.md` の目次に 1 行足す**

目次の表の最後の行の後に足す:

```markdown
| 会社PCの NixOS-WSL | 秘密情報と外部への接続経路を持たない `nixos-wsl` の導入、deploy key での agents-private の clone、会社の git と SSH の設定、更新手順 | [wsl.md](./wsl.md) |
```

- [ ] **Step 5: `docs/architecture/wsl.md` を実装済みにする**

冒頭の「設定ファイル」の行と「**現状：一部実装済み。**」の段落（3〜6 行目。パート A の最終レビューのあとで書き換えた状態）を次に置き換える。`docs/architecture/README.md` の `wsl.md` の行は Step 6 で置き換える:

```markdown
設定ファイル: [hosts/nixos-wsl/default.nix](../../hosts/nixos-wsl/default.nix)、[hosts/nixos-wsl/home.nix](../../hosts/nixos-wsl/home.nix)、[modules/nixos/base.nix](../../modules/nixos/base.nix)、[profiles/home/pomu-agents.nix](../../profiles/home/pomu-agents.nix)

導入と更新の手順は [docs/howtouse/wsl.md](../howtouse/wsl.md) を参照。
```

「## 移行手順」の節と「## ドキュメントの更新計画」の節を丸ごと削除する（済んだ作業の記録はコミットメッセージにある）。

本文中の「初回のみFlakesを一時的に有効化して実施する」の記述が残っていれば、「`nixos-rebuild` が flakes の機能を自分で有効にするので、初回も設定なしで switch できる（nixos-rebuild-ng の `nix.py` の `FLAKE_FLAGS`）」の趣旨に直す。「設計段階」「予定」「作成します」のように未実装を前提にした言い回しが残っていれば、現在の状態を述べる形に直す。

- [ ] **Step 6: `docs/architecture/README.md` の `wsl.md` の行から「未実装」を外す**

```markdown
| [wsl.md](./wsl.md) | 会社 PC の NixOS-WSL を CLI だけの閉じたホスト（`nixos-wsl`）として持つ判断。age 鍵と tailnet を持たせない理由、agents-private を読み取り専用の deploy key と別名のホストで入れる理由、共通の設定を `base.nix` に切り出す判断 |
```

- [ ] **Step 7: 検証してコミットする**

```bash
cd ~/sagyo/flake_public
python3 scripts/check-docs.py . && git diff --check
git add docs/howtouse/wsl.md docs/howtouse/README.md docs/architecture/wsl.md docs/architecture/README.md
git commit -m "docs: nixos-wsl の手順を追加し、standalone の pomu-wsl を消す"
```

コミットには Task 4 でステージした変更も入る。本文には、`pomu-wsl` から移るときに一度だけ要る作業（WSL 上の standalone Home Manager の世代が残ること、新しいイメージを入れ直す場合は不要なこと）を書く。

### Task 6: 全体を検証し、実機での確認項目を報告する

**Files:** なし

- [ ] **Step 1: 全体の検証を desktop で行う**

```bash
cd ~/sagyo/flake_public
bash scripts/check.sh
nix build --no-link --no-update-lock-file .#nixosConfigurations.nixos-wsl.config.system.build.toplevel
```

Expected: どちらも失敗しない。

- [ ] **Step 2: 作業用のファイルを消す**

```bash
cd ~/sagyo/flake_public
rm -r .git/nixos-wsl-plan
rm docs/superpowers/plans/2026-09-30-nixos-wsl-host.md
rmdir -p docs/superpowers/plans 2>/dev/null || true
git status --short
```

Expected: `git status --short` が何も出さない。

- [ ] **Step 3: 報告する**

評価とビルドで確かめたことと、実機でしか確かめられないことを分けて報告する。実機でしか確かめられないのは、初回の switch（`github:` 指定）、WSL を再起動したあとのホスト名とログイン、Neovim、deploy key での clone と pull、会社用の鍵を書いたあとの `ssh -G` の結果、`/etc/claude-code/managed-settings.json` のリンク先。
