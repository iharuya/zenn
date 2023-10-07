---
title: "ERC-165日本語訳と解説"
emoji: "🛠️"
type: "tech"
topics:
  - "solidity"
  - "ethereum"
  - "web3"
  - "スマートコントラクト"
  - "eip"
published: true
published_at: "2023-03-01 17:54"
---

# ERC-165: Standard Interface Detection
https://eips.ethereum.org/EIPS/eip-165

## はじめに
[このシリーズやERC全般についてはこちらのはじめに解説しています](https://zenn.dev/ishiharu/articles/ab576d5853aa04)

今回はEVMで規格に基づいたスマートコントラクトや任意のスマコンを利用するアプリを開発しているときに出くわすちょっと厄介なやつ（`supportsInterface()`）の規格について抄訳と少しの解説を残します。

## ERC-165を一言でいうと
「あるスマートコントラクトがどのようなインターフェース（機能）を持っているかを公開・検知するための規格」

以下ERC-165については、それを実装したSolidityコントラクトとそれを利用するプログラム
（Solidityコントラクトに限らない）の２者の存在を意識すると読みやすいです。

## 概要
以下のことを規格化する。
- インターフェースがどのように特定されるか
- コントラクトはどのようにインターフェースを外部に提供するか
- あるコントラクトがERC-165を実装しているか検知する方法
- あるコントラクトが、あるインターフェースを持っているか検知する方法

## 動機
ERC-20で定義されたような「標準インターフェース」を持つようなコントラクトとの対話方法を適合させるために、コントラクトがそのインターフェースをサポートしているか、しているならどのバージョンなのかということを問い合わせられると便利である。特にERC-20についてはそのバージョン識別方法が提案されている。ここでは、インターフェースの概念とその識別の規格化を提案する。

## 仕様
### インターフェースの識別方法
この規格でのインターフェースとは[Ethereum ABIで定義される関数セレクター](https://docs.soliditylang.org/en/develop/abi-spec.html#function-selector)の集まりのことである。これはSolidityが提供するインターフェースの概念の中の一部である。Solidityで提供される`interface`キーワードはその関数セレクターの他にも、戻り値の型、ミュータビリティ、イベントも定義される。
 
ここでは、インターフェース識別子(interfaceID)をインターフェース内の全ての関数セレクターのXORとして定義する。以下のコードはそれを計算する例である。

```solidity
pragma solidity ^0.4.20;
interface Solidity101 {
	function hello() external pure;
	function world(int) external pure;
}
contract Selector {
	function calculateSelector() public pure returns (bytes4) {
		Solidity101 i;
		return i.hello.selector ^ i.world.selector;
	}
}
```

関数セレクターとはリンクを参照すれば分かるように、ある[関数のシグネチャー](https://developer.mozilla.org/en-US/docs/Glossary/Signature/Function)のハッシュの始め4バイトである。例えば `bytes4(keccak256('hoge(uint256)'));` のようにして取得できる。したがってそれらのXORであるインターフェース識別子も4バイトとなる。

注：インターフェースはオプショナルな関数を許可しない。([参考](https://github.com/ethereum/solidity/issues/232))

### コントラクトが自身のインターフェースを外部に提供する方法
コントラクトがERC-165準拠の場合、以下のインターフェースを実装しなくてはいけない。(`ERC165.sol`というファイル名で)

```solidity
pragma solidity ^0.4.20;
interface ERC165 {
	/// @param interfaceID (上で定義)
	/// 30,000 gas以下
	/// @return コントラクトが`interfaceID`になるようなインターフェースを
	///  実装していてかつ、`interfaceID`が`0xffffffff`でない場合はtrue
	///  そうでない場合はfalse
	function supportsInterface(bytes4 interfaceID) external view returns (bool);
}
```

これは「あるコントラクトが特定のインターフェースを実装しているかを返す関数」のインターフェースである。これ自身のインターフェース識別子(0x01ffc9a7)もERC-165を実装してあるか確認するのに使われる。ややこしいけど自己説明的でイイネ😀。

### コントラクトがERC-165を実装しているか検知する方法
省略。後述するケーススタディのソースコードを適宜参照してください。

### コントラクトが特定のインターフェースとなる実装をしているか検知する方法
- まずそのコントラクトがERC-165準拠であるかわからない場合は上の方法（省略）で確認する。
- もし準拠していない場合は古い方法でそれがどんなメソッドを持っているか確認しなければいけない。
- 準拠している場合は `supportsInterface(interfaceID)` を呼んで確認すればいい。

## 実装
`mapping(bytes4 => bool) supportedInterfaces` に各コントラクトが自身のインターフェース識別子を追加していき、そのマッピングを参照するだけの共通な `supportsInterface` 関数を用意するタイプと、各コントラクトが全ての継承元のインターフェース識別値を取得してorでの真偽を返す `supportsInerface` 関数をそれぞれ用意するタイプが紹介されている。前者はgasが高いが簡単で、後者はgasは安いが難しいと言われているが、プロダクションでは後者がいいと思われる。詳しくは原文を参照。

## ケーススタディ
### CryptoKitties
(こちらのソースコード)[https://etherscan.io/address/0x06012c8cf97bead5deae237070f9587f8e7a266d#code]の1374行目から始まる`ClockAuction`コントラクトでは、オークションで扱うNFTは別のコントラクトを利用することを前提としている。コンストラクターでその外部のNFTコントラクトを登録する手続きがL1387~L1394に見ることができ、そこでは対象となるコントラクトがERC-721準拠のインターフェース（ID：0x9a20483d）をサポートしているか確認している。ERC-721はERC-165準拠であるためにこのIDが使える。