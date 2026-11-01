# TorqueController

トラックパッドだけでキーボード操作を完結させる、Mac専用のスクリーンキーボード。設計は [DESIGN.md](DESIGN.md) を参照。

## ビルドと起動

初回だけ、ローカル署名用の証明書を作る。再ビルドしてもアクセシビリティの許可が外れないようにするためのもの。

```bash
scripts/create-signing-identity.sh
```

```bash
scripts/build-app.sh
```

```bash
open .build/app/TorqueController.app
```

初回の起動時に、システム設定の「プライバシーとセキュリティ > アクセシビリティ」で TorqueController を許可する。

## 変換エンジン

辞書データは git に含めない。固定した版の Mozc のデータを取得し、バイナリに変換する。

```bash
scripts/fetch-dictionary.sh
```

```bash
scripts/build-dictionary.sh
```

読みを渡すと、列ごとの候補とスコアの内訳を表示する。

```bash
.build/release/torque-cli こんばんには
```

## ライセンス

辞書データは Mozc の dictionary_oss(語彙と接続コストは IPAdic と沖縄辞書に由来)を使う。著作権表示と許諾文は [ThirdParty/Mozc-LICENSE.txt](ThirdParty/Mozc-LICENSE.txt) にある。

## 使う権限

- アクセシビリティ: 対象アプリへキー入力を送るために使う。

## 止め方

通常はメニューバーのアイコンから「TorqueController を終了」を選ぶ。

メニューが使えないときは、ターミナルから止める。

```bash
pkill -x TorqueController
```

それでも止まらないときは、強制終了する。

```bash
pkill -9 -x TorqueController
```

修飾キーを押したままにする送り方はしないので、強制終了しても押下中の状態は残らない。
