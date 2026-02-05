import * as z from "zod";

// シンプルなスキーマ定義
const userSchema = z.object({
  name: z.string(),
  age: z.number(),
});

// バリデーション実行
const result = userSchema.safeParse({ name: "test", age: 25 });
console.log(result.success);
