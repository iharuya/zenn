import * as z from "zod/mini";

// zod/miniは関数型APIを使う
const userSchema = z.object({
  name: z.string(),
  age: z.number(),
});

const result = z.safeParse(userSchema, { name: "test", age: 25 });
console.log(result.success);
