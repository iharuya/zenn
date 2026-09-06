---
title: "AIが覚えるべきルールは少ない方が良い。〜Piでの実践例〜"
emoji: "🧑🏻‍⚖️"
type: "tech"
topics: ["picodingagent", "AIエージェント", "ClaudeCode", "Codex", "ハーネスエンジニアリング"]
published: false
---

AI、何度言っても`npm`とか`npx`を使おうとする。僕は`pnpm`で統一したいのに。

そういう、従わなくても一応動いてしまうことを、諸般の理由で一旦止めて指示を出す人は多いと思う。僕もそう。ただ、コンテキストが長くなると途中のそうした指示は忘れ、また同じことを言う羽目になるのはしんどい。それってもしかしたら賢いAIからすれば、Userのつまらん小言にすぎないのかも知れないが。

そんな僕に[Pi Coding Agent](https://pi.dev/)がドンピシャだった。どんなLLMでも使えるOSSのコーディングエージェントで、Typescriptで振る舞いを拡張できる。なんとそれは、そういう僕の小言を確実に聞いてくれるようにしてくれた。

## AIが覚えるべきルールは少ない方が良い

昔、ループの書き方や`type`と`interface`の使い分けをドキュメントに書いて、人間がレビューで指摘する現場があった。僕はあれが嫌で、linterやformatterを入れたり、プロジェクト固有のルールをASTやDSLで書いたりしてきた。

一貫して根底にあったのは、**「人間が覚えるべきルールは少ないほうがいい」** という考えだった。

そして現在、それはAI相手でも同じだと思っている。

もちろん設計の相談は自然言語でする。でも、機械的に判定できることまで「ちゃんと覚えていてね」に賭けたくない。**プロンプトは祈りだ。コードだけがルールである。** 少なくとも、この手の小言については。

Piでは、[拡張機能](https://github.com/earendil-works/pi/blob/fcff255b004a6cde812b5b7a714e0bfe9c540986/packages/coding-agent/docs/extensions.md)からツール実行直前の`tool_call`イベントを受け取れる。そこで自由にTypescriptでロジックを書いて、条件にマッチしたらブロックして理由をAIに返せる。

## 祈るのではなくコードを定める

### pnpmしか使わないでおくれ

僕の拡張は、Bashで`npm`・`npx`・`yarn`を実行しようとしたらブロックする。肝はこの返り値だけ。

```ts
return {
  block: true,
  reason: "ここではpnpmを使用します。npmの代わりにpnpmを使用してください。",
};
```

実行してから怒るのではなく、実行前に止める。理由を日本語で書いておけば、画面を見ている僕にも何が起きたかわかる。地味だけど嬉しい。

:::details 実際に使っている拡張コード（Pi v0.85.1）
```ts
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BLOCKED_COMMANDS = [
  {
    regex: /^npx\b/,
    manager: "npx",
    suggestion: "`npx`の代わりに`pnpm dlx`や`pnpm exec`を使用してください。",
  },
  {
    regex: /^npm\b/,
    manager: "npm",
    suggestion: "`npm`の代わりに`pnpm`を使用してください。",
  },
  {
    regex: /^yarn\b/,
    manager: "yarn",
    suggestion: "`yarn`の代わりに`pnpm`を使用してください。",
  },
];

function checkBlockedCommand(command: string) {
  const statements = command.split(/&&|\|\||;|\|/).map((s) => s.trim());

  for (const stmt of statements) {
    if (!stmt || /^(pnpm|bun|deno)(\s+.*)?$/i.test(stmt)) continue;

    for (const { regex, manager, suggestion } of BLOCKED_COMMANDS) {
      if (regex.test(stmt)) {
        return { manager, suggestion };
      }
    }
  }
  return null;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    const toolName = event.toolName.toLowerCase();
    if (toolName !== "bash" && !toolName.endsWith(":bash")) return;

    const input = event.input as { command?: string } | undefined;
    const command = input?.command || "";
    const blocked = checkBlockedCommand(command);
    if (!blocked) return;

    if (ctx.hasUI) {
      ctx.ui.notify(`${blocked.manager}の使用をブロックしました`, "warning");
    }

    return {
      block: true,
      reason:
        `🚫 ここでは \`pnpm\` を使用します。\n` +
        `💡 ${blocked.suggestion} \n` +
        "どうしてもpnpmではなくnpmを使わなければいけない場合は、立ち止まってユーザーに確認してください。",
    };
  });
}
```
:::

ただし、これはシェル構文を網羅した検査ではない。たとえば`env npm install`は拾えない。悪意ある操作を封じる仕組みではなく、よくある脱線を止めるための、自分用のルールだ。

### 計画書に番号を振らないでおくれ

AIに計画を立てさせると、すぐこういう`plan.md`を書く。

```md:plan.md
## phase 1: 認証APIの実装
## phase 2: ログイン画面の実装
## phase 3: E2Eテストの追加
## ...
```

ほんとやめてほしい。テストの前に「パスワード再設定機能の実装」というフェーズを挟むだけで、後ろの番号まで直すことになる。見出しには何をやるかだけ書いてくれればいいのに。

なので、`write`や`edit`の入力を検査して、ドキュメントに番号付きの表記を見つけたら止める拡張も作った。「見出しから番号やphase表記を消して、やることだけ書いて」と理由を返す。

番号が役立つ場面もあるだろうけど、僕の作業環境ではまず禁止する。このへんは遠慮なく自分の好みに寄せている。

## 誤検知したら、プロンプトではなくテストを直す

当然、数字を片っ端から弾けばいいわけではない。例えば、`1.はじめに`はナンバリングだけど、`1.29 GB`はナンバリングじゃない。実際の判定関数のテストを少し抜粋すると、こんな感じ。

```ts
expect(checkNumberedPattern("1.はじめに")).not.toBeNull();
expect(checkNumberedPattern("1.29 GB")).toBeNull();
```

「それ、自作linterのメンテをするだけでは？」と言われたら、その通り。誤検知も検知漏れもあり得るし、この拡張が見ている`write`・`edit`以外の書き込み経路まで塞いでいるわけでもない。

それでも僕は、「番号振るのはやめてね！例えばxxxとかyyyとか...」とプロンプトで祈るより、テストケースを足して判定を直すほうが好きだ。「この入力は止める、これは通す」が残る。AIの性能によらず、同じ判定コードとテストに従う。

これはいい。

AIの振る舞いのうち、自分が気にする部分が少しずつ仕様になっていく。この、自分のコントロール下に置いている感じが、なんと言うか、めっちゃ安心する。 ~~AIに対するメンヘラは許して~~

## 拡張機能は、あえて自分で作りたい

`Pi`では[誰かが作った拡張機能](https://pi.dev/packages)を入れることもできる。でも僕は今のところ、全部小さく自作している。

一般的に必要とされる以下のような機能はPiにデフォルトで入っていない。

- ガードレール
- 並列駆動
- Plan
- MCP
- Web検索
- 編集時に自動で`pnpm run fix`などを実行するフック

さっき紹介した個人的なルールはともあれ、こう言う機能は用意してくれよ、と思うかも知れない。でもデフォルトのPiはコーディングエージェントとして最低限であり、拡張して使うことが前提であるという強いメッセージを感じる。

といっても全部手書きするわけではない。Pi自身にドキュメントや実装例を読ませて相談する。[narumiruna氏の拡張セット](https://github.com/narumiruna/pi-extensions)も参考になった。ただし、汎用性やリッチなTUIは要らないから、自分に必要なところだけ作ってもらう。するとコード量は体感で20%ぐらいに削減できる。

その自分だけの拡張機能は`~/pi-config`のような設定リポジトリに置き、シンボリックリンクで適用する運用に落ち着いた。要するにdotfilesだ。今、10個ぐらいの拡張機能があるけど、へへ、満足感がすごい。

AIに書かせた設定に愛着なんて湧くのか、と思うかもしれない。僕は湧いた。「こういうやり方にしたい」「ここは止めてほしい」「それは通していい」と何度もやり取りして、だんだん自分好みのAI Agentになっていく。VimやEmacsを育てる人たちの気持ちにちょっと近いのかもしれない。いや、その比較はおこがましいか。僕は公式ドキュメントを読んだり試行錯誤をせず、楽をしてここまできたのだから。

ともあれ。

Anthropicのモデルを使うなら、Claude Codeの方が賢いだろう。

OpenAIのモデルを使うなら、Codexを使った方が賢いだろう。

けど、いずれにせよもう十分すぎるほど賢い。

なら、その8割の賢さでもいい。いや、もしかしたら2割でもよくなるのかも知れない。とにかく、僕は自分で育てた`Pi`を使いたいと思ったのでした。

