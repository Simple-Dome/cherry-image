import { describe, expect, test } from "bun:test";

import { getVideoPollingPolicy, readVideoSeed, type VideoGenerationTask } from "./video";

describe("readVideoSeed", () => {
    test("does not send Seed while the switch is off", () => {
        expect(readVideoSeed({ videoSeedEnabled: "false", videoSeed: "123" })).toBeUndefined();
    });

    test("keeps Seed 0 when the switch is on", () => {
        expect(readVideoSeed({ videoSeedEnabled: "true", videoSeed: "0" })).toBe(0);
    });

    test("rejects an invalid enabled Seed", () => {
        expect(() => readVideoSeed({ videoSeedEnabled: "true", videoSeed: "1.5" })).toThrow("Seed 必须是 0–4294967295 的整数");
    });

    test("accepts the 431 unsigned 32-bit maximum", () => {
        expect(readVideoSeed({ videoSeedEnabled: "true", videoSeed: "4294967295" })).toBe(4_294_967_295);
    });
});

describe("getVideoPollingPolicy", () => {
    test("polls OpenAI-compatible video tasks long enough for slow upstream completion", () => {
        const task: VideoGenerationTask = { id: "task_test", provider: "openai", model: "video-ds-2.0-fast" };

        const policy = getVideoPollingPolicy(task);

        expect(policy.delayMs).toBe(5000);
        expect(policy.maxAttempts * policy.delayMs).toBeGreaterThanOrEqual(20 * 60 * 1000);
        expect(policy.timeoutMessage).toBe("视频生成超时，请稍后重试");
    });

    test("keeps Seedance polling at the existing ten minute window", () => {
        const task: VideoGenerationTask = { id: "task_seedance", provider: "seedance", model: "seedance" };

        const policy = getVideoPollingPolicy(task);

        expect(policy.delayMs).toBe(5000);
        expect(policy.maxAttempts * policy.delayMs).toBe(10 * 60 * 1000);
        expect(policy.timeoutMessage).toBe("Seedance 视频生成超时，请稍后重试");
    });

    test("uses the long polling window for 933 Jimeng tasks", () => {
        const task: VideoGenerationTask = { id: "task_jimeng", provider: "jimeng933", model: "firefly-video-v2" };

        const policy = getVideoPollingPolicy(task);

        expect(policy.delayMs).toBe(5000);
        expect(policy.maxAttempts * policy.delayMs).toBeGreaterThanOrEqual(20 * 60 * 1000);
    });

    test("uses the long polling window for 431 Jimeng tasks", () => {
        const task: VideoGenerationTask = { id: "task_jimeng_431", provider: "jimeng431", model: "leonardo-seedance-2.0" };
        const policy = getVideoPollingPolicy(task);
        expect(policy.delayMs).toBe(5000);
        expect(policy.maxAttempts * policy.delayMs).toBeGreaterThanOrEqual(20 * 60 * 1000);
    });
});
