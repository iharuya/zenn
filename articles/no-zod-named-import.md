---
title: "Zod v4、インポート方法で300KB→66KBに。あなたのコードは大丈夫？"
emoji: "😈"
type: "tech"
topics: ["zod", "biome"]
published: false
---

# あなたのZod、全部入りになっていませんか？

Zod v3時代、多くのプロジェクトでこんなインポート文を書いていたはずです。

```ts
import { z } from "zod";
```

これは**Named import（名前付きインポート）** と呼ばれる書き方です。Zod v4にアップグレードしても、このコードは問題なく動きます。型エラーも出ません。

しかし、この書き方には**ツリーシェイキングを阻害する**という落とし穴があります。代わりに使うべきは **Namespace import（名前空間インポート）** です。

```ts
import * as z from "zod";
```

どの程度影響があるのか、実際に検証してみました。細かいことはいいので何をすべきか早く知りたいかたは[#やるべきこと](#やるべきこと)へどうぞ。

# 検証：インポート方法でバンドルサイズはどれだけ変わるのか

実際に検証してみました。

**検証環境**
- Zod v4.3.6
- esbuild 0.27.2
- ビルドコマンド: `esbuild index.ts --bundle --minify --format=esm --platform=node`

**検証コード**（全パターン共通のロジック）

```ts
const userSchema = z.object({
  name: z.string(),
  age: z.number(),
});

const result = userSchema.safeParse({ name: "test", age: 25 });
console.log(result.success);
```

たったこれだけのシンプルなスキーマ定義で、インポート方法だけを変えて比較しました。

## 結果

| インポート方法 | バンドルサイズ | gzip後 |
|---|---|---|
| `import { z } from "zod"` | 303.24 KB | 60.43 KB |
| `import * as z from "zod"` | 66.28 KB | 18.40 KB |
| `import * as z from "zod/mini"` | 9.98 KB | 3.92 KB |

この検証コードでは、名前付きインポートが名前空間インポートの**約4.6倍**のバンドルサイズになりました。

## バンドル内容の分析

生成されたJavaScriptを分析すると、違いがより明確になります。

**名前付きインポート（303KB）**
- バンドルに含まれるZod型: **99種類**
- `ZodAny`、`ZodBigInt`、`ZodBoolean`、`ZodDate`など、コードで使っていない型がすべて含まれている
- バンドル冒頭でZodの全エクスポートを列挙している

**名前空間インポート（66KB）**
- バンドルに含まれるZod型: **60種類**
- 使用している`ZodObject`、`ZodString`、`ZodNumber`と、それらが内部で依存する型のみ

名前空間インポートでも完全なツリーシェイキングにはならない点に注意してください。Zodのメソッドチェーン設計上、ある程度の依存関係は含まれます。ただし、名前付きインポートではそれに加えてZodの全APIがバンドルに含まれてしまうため、大幅にサイズが増加します。

:::message
この数値は今回の検証コードでの結果です。実際のプロジェクトでは、アプリケーション全体のコードサイズに対する比率で影響度が変わります。
:::

# なぜ名前付きインポートだとツリーシェイキングが効かないのか

これはZodのAPI設計とバンドラーの特性に起因します。

Zodはメソッドチェーンを多用するAPIです。

```typescript
z.string().optional().nullable().default("hello")
```

バンドラー（esbuild、webpack、rollupなど）は**トップレベル関数の未使用コード削除は得意**ですが、**オブジェクトのメソッドの削除は苦手**です。

`import { z } from "zod"` と書くと、`z` オブジェクトへの参照が作られます。Zod v4において、名前付きエクスポートの `z` は後方互換性のために用意された全機能を含む巨大なオブジェクトです。バンドラーはこのオブジェクト全体が必要だと判断し、結果としてすべての機能がバンドルに含まれてしまいます。

一方、`import * as z from "zod"` の名前空間インポートでは、バンドラーが各エクスポートの使用状況を個別に追跡できるため、`z.string` や `z.object` といった個別のトップレベルエクスポートへのアクセスとして解決され、ツリーシェイキングが正しく機能します。

Zod公式も名前空間インポートを推奨しており、これを強制するESLintプラグイン（[eslint-plugin-import-zod](https://github.com/samchungy/eslint-plugin-import-zod)）も存在するほどです。私はBiomeが好きなので、カスタムプラグインで同等のことを行う方法を後述します。

# やるべきこと

## Step1：既存のインポート文を書き換える

対策は簡単です。インポート文を書き換えるだけ。

```diff
- import { z } from "zod";
+ import * as z from "zod";
```

コード本体の変更は一切不要です。`z.string()`、`z.object()` などの呼び出しはそのまま動きます。今すぐ一括Grepしましょう。

:::details 「import { string, object } from "zod" じゃダメなの？」
ツリーシェイキングの文脈では、必要なものだけを個別にインポートする重要性が強調されます。

```ts
import { string, object, number } from "zod";

const userSchema = object({
  name: string(),
  age: number(),
});
```

このようなやり方を徹底できるのなら最強です。

しかし、Zodは `z.string()` のようにネームスペース的な使い方が広く浸透しています。これは今の時代、デファクトと言ってしまっても過言ではないでしょう。人間からしたらめんどくさい作業だし、AIに要求するにも認知（コンテキスト）負荷でしかないためです。あとZodの場合、`string()`といった関数名が予約語と衝突しそうで怖いなと感じてしまいます。
:::

## Step2：Biomeで強制する

既存コードは救われました。ただ、これから書かれるコードについてはどうでしょうか？

今やAIがコードを書く時代ですが、AI達の知識も古いままです。無理やりプロンプトで上記のルールを示したところで複雑で大規模なタスクの中ではほぼ無意味です。そこで、これを自動ルールにすることが非常に大きな価値となります。ここではBiomeのカスタムプラグイン機能を使った事例を紹介します。

まず、プロジェクトにGritパターンファイルを作成します。場所は適当に`biome/no-zod-named-import.grit`とします。
```grit
`import { $imports } from "zod"` where {
    register_diagnostic(span=$imports, message="Use namespace import: import * as z from 'zod'", severity="error")
}
```

次に、`biome.jsonc` でプラグインを有効にします。

```json:biome.jsonc
{
  "plugins": ["./biome/no-zod-named-import.grit"]
}
```

これだけで、`import { z } from "zod"` を書くとエディタ上でエラーが表示されます。

![Biomeが警告してくれているのをVSCodeで確認するデモ](/images/no-zod-named-import/biome-warning.png)

Biomeのカスタムプラグインは現時点では自動修正（`--fix`）に対応していませんが、エラーメッセージが明確なので[Hooks (kazuph氏の記事を参考までに)](https://zenn.dev/kazuph/articles/483d6cf5f3798c)とかでBiomeチェックを頻繁に実行させていればAIが気づいて修正してくれるでしょう。実際に著者はこれで非常に助かっています。

## Step3（Optional）：さらに軽量化するなら zod/mini

検証結果を見ると、`zod/mini` は驚異的な軽さです。

| パッケージ | gzip後サイズ |
|---|---|
| zod（名前空間インポート） | 18.40 KB |
| zod/mini | 3.92 KB |

`zod/mini` はツリーシェイキングに特化した関数型APIを提供します。メソッドチェーンではなく、関数でラップするスタイルです。

```ts
import * as z from "zod/mini";

// メソッドチェーンではなく関数でラップ
const schema = z.optional(z.string());
```

APIが通常のZodと異なるため、既存コードの書き換えが必要になります。バンドルサイズに厳しい制約がある場合（エッジ環境、モバイルWebなど）は検討する価値があります。

# まとめ

- `import { z } from "zod"` は**ツリーシェイキングが効かず、バンドルサイズが4倍以上**になる場合がある
- `import * as z from "zod"` に書き換えるだけでいい。（※ただし、ツリーシェイキングが有効なバンドラ設定が必要）
- Biomeのカスタムプラグインで自動ルール化すると、AIも人間もハッピーになれる
- 極限まで軽量化したいなら `zod/mini` も選択肢

Zod v3からv4に移行したプロジェクトは、ぜひインポート文を確認してみてください。
