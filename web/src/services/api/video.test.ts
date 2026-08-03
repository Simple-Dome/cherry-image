import { describe, expect, test } from "bun:test";

import { getVideoPollingPolicy, type VideoGenerationTask } from "./video";

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
});
