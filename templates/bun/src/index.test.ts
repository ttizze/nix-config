import { describe, expect, test } from "bun:test";

import { greeting } from "./index";

describe("greeting", () => {
  test("greets the supplied name", () => {
    expect(greeting("Nix")).toBe("Hello, Nix!");
  });
});
