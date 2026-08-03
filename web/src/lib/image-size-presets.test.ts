import { describe, expect, test } from "bun:test";

import { findImageSizePreset, imageSizePresetSummary, resolveCanvasImageRequestSize, resolveImagePresetSize } from "./image-size-presets";

describe("image size presets", () => {
    test("maps common ratios to explicit 1K, 2K and 4K dimensions", () => {
        expect(resolveImagePresetSize("1K", "16:9")).toBe("1280x720");
        expect(resolveImagePresetSize("2K", "16:9")).toBe("2560x1440");
        expect(resolveImagePresetSize("4K", "16:9")).toBe("3840x2160");
        expect(resolveImagePresetSize("4K", "1:1")).toBe("2880x2880");
        expect(resolveImagePresetSize("4K", "4:3")).toBe("3200x2400");
        expect(resolveImagePresetSize("4K", "9:16")).toBe("2160x3840");
    });

    test("infers the selected tier and ratio from explicit dimensions", () => {
        expect(findImageSizePreset("2880x2880")).toEqual({ tier: "4K", ratio: "1:1" });
        expect(findImageSizePreset("2048x1536")).toEqual({ tier: "2K", ratio: "4:3" });
        expect(imageSizePresetSummary("3840x2160", "auto")).toBe("4K · 16:9");
    });

    test("preserves legacy ratio-derived dimensions for existing canvas nodes", () => {
        expect(resolveCanvasImageRequestSize("1:1", "high")).toBe("2880x2880");
        expect(resolveCanvasImageRequestSize("4:3", "high")).toBe("3312x2480");
        expect(resolveCanvasImageRequestSize("9:16", "medium")).toBe("1536x2720");
        expect(resolveCanvasImageRequestSize("auto", "auto")).toBe("1024x1024");
    });
});
