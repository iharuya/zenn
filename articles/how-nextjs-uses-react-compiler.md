---
title: "Next.js はどうやって React Compiler を実行しているのか"
emoji: "🤝"
type: "tech"
topics: ["next.js","react","frontend","rust"]
published: true
---

## はじめに：React Compilerの登場と、Next.jsにおける疑問

2025/04/21、Reactチームは待望の[React Compilerの安定版リリース候補](https://react.dev/blog/2025/04/21/react-compiler-rc)を発表しました。このCompilerは、Reactコンポーネントが不要な再レンダリングを自動的にスキップできるようにコードを最適化し、開発者が手動で`useMemo`や`useCallback`といった最適化フックを記述する負担を減らすことを目指しています。

Next.jsでは、[v15からReact Compilerを実験的にサポート](https://nextjs.org/blog/next-15-rc#react-compiler-experimental)するようになりました。

ただ、React Compilerが記事執筆時点でBabelプラグインとしてしか提供されていない点が気になります。

近年、Next.jsは高速なRustベースのコンパイラである[SWC](https://swc.rs/)を積極的に導入し、Babelへの依存を減らしてきました。それによってビルド速度が劇的に向上したことを体感している方も多いでしょう。

SWCが主流となっているNext.jsにおいて、BabelプラグインであるReact Compilerはどのように統合されているのでしょうか？

[公式ドキュメントでの説明](https://nextjs.org/docs/app/api-reference/config/next-config-js/reactCompiler)がふわっとしてたので、2025/08/22 時点のNext.js Canary版のソースコードを使って解説します。

なお、実際にNext.jsでReact Compilerを有効にした際に、どのようなコードがビルドされるのか、より具体的な変換結果については、mugiさんの記事が非常に参考になります：

https://zenn.dev/cybozu_frontend/articles/next-react-compiler

## 結論：SWCとBabelのハイブリッド戦略

Next.jsがReact Compilerを統合するために採用しているアプローチは、**SWCとBabelのハイブリッド戦略**です。

端的に言えば、Next.jsは以下のステップでReact Compilerを実行しています。

1.  **SWC (Rust)** でソースコードをパースし、そのASTを利用して、**React Compilerを適用すべきファイルかどうか**を高速に判定
2.  判定で`true`になったファイルのみ、Babel Loaderを介してReact CompilerのBabelプラグインが実行される

つまり、全てのJavaScript/TypeScriptファイルをBabelに通すのではなく、SWCが前処理として対象ファイルを絞り込むことで、SWCの高速性を最大限に活かしつつ、BabelプラグインであるReact Compilerの機能を統合しているのです。

ではこれが具体的にコードレベルでどのように実現されているのかを見ていきましょう。

## コードリードしていく

Next.jsは、Rustで書かれたSWCのカスタムトランスフォームを使用して、1つのファイルがReact Compilerの対象となるべきかを判定します。

https://github.com/vercel/next.js/blob/4b567eb0bfec14e51ca74fdfa2b44dd60a87047b/crates/next-custom-transforms/src/react_compiler.rs#L16-L127

このRustコードでは、SWCがパースしたASTを使い、以下のような特徴を持つ関数やコンポーネントを探します。

-   **大文字で始まる関数名**: 通常のReactコンポーネントの命名規則（例: `function MyComponent() {...}`）
-   **"use"で始まる関数名**: React Hooksっぽいもの
-   `export default`された関数
-   これらの関数内でJSX要素が使われているか

この判定ロジックは、**偽陰性（本当はコンパイラを適用すべきなのに誤って不要と判断してしまう）が低くなるように判定する**ことを重視していることを感じます。

Rustで実装された判定ロジックをTSで叩くバインディング：

https://github.com/vercel/next.js/blob/4b567eb0bfec14e51ca74fdfa2b44dd60a87047b/packages/next/src/build/swc/index.ts#L1554-L1559

このとき、RustからTypeScriptに渡されるデータは`true`か`false`という**極めて小さな情報**である点が重要です。プロセスを跨いでAST全体を渡すような高コストな処理は発生しません。

この判定結果を受け取ってBabelローダーの設定を動的に生成しています：

https://github.com/vercel/next.js/blob/0ed99f10c97e9cca47aad6d31023c9604a11c320/packages/next/src/build/babel/loader/get-config.ts#L369-L374

ここで、SWCから渡された判定結果が`true`の場合、React CompilerのBabelプラグインが設定に追加されます。

また、この部分で前提条件とされている`standalone`モードとは、Next.jsが提供するデフォルトのビルドプロセスでSWCローダーがメインで使用される場合を指します。もしアプリケーション開発者が独自に`.babelrc`などのBabel設定ファイルを設置している場合、Next.jsは開発者の設定を優先するため、React Compilerプラグインはご自身で設定いただく必要があります。

## おわりに

React Compilerを適用する対象として、`node_modules`を除外するのは当然ですが、それに加え、上記のような高度な判定を行っていることが分かりました。

今回読んできたコードのほとんどは、このPRで追加されたものです：https://github.com/vercel/next.js/pull/75605

この変更は、特に大規模なプロジェクトにおいてビルド時間を最適化するための工夫と言えます。

Babel/SWCが協調しているこの珍妙なコードは、SWCネイティブのReact Compilerがリリースされるまでの一時的な解決策でしょう。

SWC版がリリースされる時期について公式の発表はありませんが、おそらく今後はBabelプラグインの一般提供（GA）-> 広範な採用とフィードバック -> 仕様の確立 -> ネイティブSWCプラグインの本格開発、といった段階を踏むのではないかと予想しています。

本記事では、Next.jsがReact Compilerをどのように実行しているかについて、その内部実装をソースコードレベルで紐解きました。




