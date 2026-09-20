# blog-sample-release-repo

複数のサービスを、それぞれのデプロイ方式 (ECS / Lambda / Cloud Run) で環境ごとにデプロイするためのリリースリポジトリです。
各アプリリポジトリはイメージをビルドして `repository_dispatch` を送るだけで、**デプロイ定義とデプロイの実行はすべてこのリポジトリが持ちます**。

## 考え方

- **サービス = ディレクトリ**: `services/<name>/` にサービスをまとめる。サービス自体に設定ファイルはない。
- **環境 = サブディレクトリ**: `services/<name>/{dev,stg,prd}/` にその環境の `env.yaml` (デプロイ方式、イメージ、接続先) と **デプロイ定義の実体** を置く。環境に依存しない設定は持たない。デプロイ方式は定義ディレクトリと 1 対 1 で、イメージの置き場も環境ごとに変わり得るため、共通層を作っても共通化されないから。環境間で定義をテンプレート共有せず、差分は `diff -r dev prd` で見える状態にする。`prd/` の変更は CODEOWNERS でレビュー必須にできる。
- **デプロイ方式はプラグイン**: `.github/actions/deploy-<kind>/` が 1 方式を担当する。`deploy.yml` は `kind` を見て振り分けるだけ。
- **環境の進み方は共通**: dev → stg → prd の順。ディレクトリが無い環境はスキップし、`requires_release: true` の環境は release タグ付きの dispatch でだけ進む。前段が失敗したら後段には進まない。
- **どこでも同じイメージ**: 全環境で同じイメージタグ (`sha-<commit>`) を使う。再ビルドはしない。

```mermaid
flowchart LR
    subgraph apps[アプリリポジトリ群]
        A1[blog-sample-app-repo1<br/>build → tagpr]
        A2[example-lambda-repo]
        A3[example-cloudrun-repo]
    end
    A1 -->|repository_dispatch<br/>service, image_tag, release_tag| R
    A2 -.-> R
    A3 -.-> R
    subgraph R[blog-sample-release-repo]
        P[params<br/>env.yaml の有無を見る] --> D[dev/] --> S[stg/] --> Pr[prd/<br/>requires_release]
    end
    D & S & Pr -->|kind: ecs| ECS[ecspresso]
    D & S & Pr -->|kind: lambda| LMB[lambroll]
    D & S & Pr -->|kind: cloudrun| CR[gcloud run]
```

## ディレクトリ構成

```
.
├── services/
│   ├── blog-sample-app/                 # 実サービス (ECS)
│   │   ├── dev/
│   │   │   ├── env.yaml                 # kind, image, aws (region / account_id / role_arn), requires_release
│   │   │   └── ecspresso/               # config.yaml, ecs-task-def.json, ecs-service-def.json
│   │   ├── stg/ …
│   │   └── prd/ …                       # requires_release: true
│   ├── example-lambda/                  # 例 (Lambda)
│   │   ├── dev/{env.yaml, lambroll/function.json}
│   │   └── prd/{env.yaml, lambroll/function.json}
│   └── example-cloudrun/                # 例 (Cloud Run)
│       ├── dev/{env.yaml, cloudrun/service.yaml}
│       └── prd/{env.yaml, cloudrun/service.yaml}
├── scripts/render.sh                    # 定義をダミー値でレンダリング (CI / ローカル共用)
└── .github/
    ├── CODEOWNERS                       # services/*/prd/ のレビュー必須化の例
    ├── actions/
    │   ├── deploy-ecs/                  # ecspresso verify / diff / deploy
    │   ├── deploy-lambda/               # lambroll diff / deploy
    │   └── deploy-cloudrun/             # envsubst → gcloud run services replace
    └── workflows/
        ├── release.yml                  # repository_dispatch を受けて dev → stg → prd
        ├── deploy.yml                   # 再利用: 1 サービス × 1 環境 (kind で振り分け)
        ├── rollback.yml                 # 手動: 任意タグの再デプロイ
        └── ci.yml                       # PR: 全サービス × 全環境の render
```

## マニフェスト: services/&lt;name&gt;/&lt;env&gt;/env.yaml

```yaml
kind: ecs                    # ecs | lambda | cloudrun (同じディレクトリの定義と対応)
requires_release: true       # release_tag 付きの dispatch でだけデプロイ (prd 向け)

image:                       # デプロイするイメージ (タグは dispatch の image_tag)
  registry: 333333333333.dkr.ecr.ap-northeast-1.amazonaws.com
  repository: blog-sample-app

aws:                         # kind が ecs / lambda の場合
  region: ap-northeast-1
  account_id: "333333333333"
  role_arn: arn:aws:iam::333333333333:role/gha-release-blog-sample-app-prd
# gcp:                       # kind が cloudrun の場合
#   project_id: …
#   region: …
#   workload_identity_provider: projects/…/providers/…
#   service_account: …
# vars:                      # 任意。デプロイ定義のテンプレートに環境変数として渡す
#   FOO: bar
```

デプロイ定義は同じディレクトリに置きます。定義の中で差し替えるのは基本的にイメージだけで、ecspresso / lambroll では `{{ must_env `IMAGE` }}`、Cloud Run の `service.yaml` では `${IMAGE}` と書きます。`ENV`, `AWS_REGION`, `AWS_ACCOUNT_ID` と `vars` の各キーも環境変数として使えます。

## デプロイ方式ごとの動き

| kind | ツール | 認証 | 実行内容 |
|---|---|---|---|
| `ecs` | [ecspresso](https://github.com/kayac/ecspresso) | AWS OIDC | `verify` → `diff` → `deploy` (サービス安定化まで待機。サーキットブレーカーで自動ロールバック) |
| `lambda` | [lambroll](https://github.com/fujiwara/lambroll) | AWS OIDC | `diff` → `deploy` (コンテナイメージ。新バージョンを publish してエイリアスを付け替え) |
| `cloudrun` | gcloud | GCP Workload Identity | `envsubst` で `service.yaml` を埋めて `gcloud run services replace` (新リビジョンが Ready になるまで待機) |

新しい方式を足すときは `.github/actions/deploy-<kind>/action.yml` を追加し、`deploy.yml` に分岐を 1 つ足します。

## 起動方法

### repository_dispatch (通常)

アプリリポジトリから GitHub App のトークンで送ります。

```json
{
  "event_type": "deploy",
  "client_payload": {
    "service": "blog-sample-app",
    "image_tag": "sha-0123abcd...",
    "release_tag": "v2026.0920.0",
    "sha": "0123abcd...",
    "source_run_url": "https://github.com/.../actions/runs/..."
  }
}
```

`release_tag` が空なら `requires_release: true` の環境 (通常は prd) はスキップされます。

### 手動

- `Release` ワークフローの `workflow_dispatch`: 同じ引数で通しのデプロイを実行します。
- `Rollback / Redeploy`: サービス、環境、イメージタグ (`sha-...` または `vYYYY.MMDD.N`) を指定して再デプロイします。

## サービスや環境を追加する

- **サービスの追加**: `services/<name>/<env>/` を必要な環境ぶん作る PR を出す。GitHub 側の設定変更は不要。
- **環境の追加**: `services/<name>/<env>/` を作る。既存の環境からコピーして値を書き換えるのが早い。
- **環境を外す**: ディレクトリを消せばその環境はスキップされる。

## セットアップ

### クラウド側 (このリポジトリの範囲外)

各サービス・環境のリソース (ECS クラスター、ALB、IAM ロール、Lambda 実行ロール、Cloud Run のサービスアカウント等) は Terraform 等で用意し、その ID や ARN を各環境ディレクトリの定義に書きます。

GitHub Actions 用のロールは **このリポジトリの環境を信頼する** ように設定します。
AWS の OIDC なら `sub` を `repo:gainings/blog-sample-release-repo:environment:<env>` に、GCP の Workload Identity なら属性条件を同様に絞ります。

### GitHub 側

- **Environments** `dev` / `stg` / `prd` を作成します。変数の設定は不要です (値はすべてリポジトリ内にあります)。`prd` に Required reviewers を設定すると、承認を挟んでから本番デプロイできます。
- **ブランチ保護**で "Require review from Code Owners" を有効にすると、`.github/CODEOWNERS` により `services/*/prd/` の変更にレビューが必須になります。
- **GitHub App**: アプリリポジトリが dispatch に使う GitHub App をこのリポジトリにもインストールします (Contents: Read and write)。

## ローカルでの確認

```sh
scripts/render.sh blog-sample-app dev
scripts/render.sh example-lambda prd
scripts/render.sh example-cloudrun dev
diff -r services/blog-sample-app/stg services/blog-sample-app/prd   # 環境差分を見る
```

`yq`, `ecspresso`, `lambroll`, `envsubst` が必要です。クラウドには接続しません。
