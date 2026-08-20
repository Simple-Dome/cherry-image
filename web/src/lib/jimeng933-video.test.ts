import { describe, expect, test } from "bun:test";

import { normalizeJimeng933Ratio, normalizeJimeng933Resolution, validateJimeng933VideoInput, type Jimeng933VideoValidationInput } from "./jimeng933-video";

const validInput: Jimeng933VideoValidationInput = {
    model: "firefly-video-v2",
    prompt: "雨后的城市街道",
    duration: 5,
    resolution: "720p",
    aspectRatio: "16:9",
    images: [],
    videos: [],
    audios: [],
};

describe("933 即梦视频参数归一化", () => {
    test("兼容当前通用分辨率配置", () => {
        expect(normalizeJimeng933Resolution("480")).toBe("480p");
        expect(normalizeJimeng933Resolution("auto")).toBe("720p");
        expect(normalizeJimeng933Resolution("high")).toBe("720p");
        expect(normalizeJimeng933Resolution("1080")).toBe("1080p");
    });

    test("只转换方案指定的尺寸比例", () => {
        expect(normalizeJimeng933Ratio("1280x720")).toBe("16:9");
        expect(normalizeJimeng933Ratio("720x1280")).toBe("9:16");
        expect(normalizeJimeng933Ratio("1024x1024")).toBe("1:1");
        expect(normalizeJimeng933Ratio("4:3")).toBe("4:3");
    });
});

describe("933 即梦视频输入校验", () => {
    test("仅接受公开模型和 5、10、15 秒时长", () => {
        expect(validateJimeng933VideoInput(validInput)).toBeNull();
        expect(validateJimeng933VideoInput({ ...validInput, model: "firefly-video-v3" })).toContain("仅支持");
        expect(validateJimeng933VideoInput({ ...validInput, duration: 6 })).toBe("933 即梦只支持 5、10、15 秒视频");
    });

    test("Fast 模型拒绝 1080p", () => {
        expect(validateJimeng933VideoInput({ ...validInput, model: "firefly-video-v2-fast", resolution: "720p" })).toBeNull();
        expect(validateJimeng933VideoInput({ ...validInput, model: "firefly-video-v2-fast", resolution: "1080p" })).toContain("不支持 1080p");
    });

    test("校验 Seed 范围", () => {
        expect(validateJimeng933VideoInput({ ...validInput, seed: 0 })).toBeNull();
        expect(validateJimeng933VideoInput({ ...validInput, seed: 2_147_483_647 })).toBeNull();
        expect(validateJimeng933VideoInput({ ...validInput, seed: -1 })).toContain("Seed");
        expect(validateJimeng933VideoInput({ ...validInput, seed: 1.5 })).toContain("Seed");
    });

    test("不在本地限制提示词、负面提示词和分镜提示词长度", () => {
        const longPrompt = "字".repeat(1501);
        expect(validateJimeng933VideoInput({ ...validInput, prompt: longPrompt, negativePrompt: longPrompt })).toBeNull();
        expect(validateJimeng933VideoInput({ ...validInput, prompt: "", shots: [{ id: "one", prompt: longPrompt, duration: 2 }, { id: "two", prompt: longPrompt, duration: 3 }] })).toBeNull();
    });

    test("有合法分镜时允许顶层提示词为空", () => {
        const shots = [
            { id: "one", prompt: "建立场景", duration: 2 },
            { id: "two", prompt: "人物入场", duration: 3 },
        ];
        expect(validateJimeng933VideoInput({ ...validInput, prompt: "", shots })).toBeNull();
        expect(validateJimeng933VideoInput({ ...validInput, prompt: "", shots: shots.map((shot) => ({ ...shot, duration: 2 })) })).toContain("分镜总时长");
    });

    test("限制图片、视频、音频和素材总数", () => {
        const image = (index: number) => ({ id: `image-${index}`, name: `${index}.png`, type: "image/png", dataUrl: `data:image/png,${index}`, bytes: 10 });
        const video = (index: number) => ({ id: `video-${index}`, name: `${index}.mp4`, type: "video/mp4", url: `blob:video-${index}`, bytes: 10, width: 1280, height: 720, durationMs: 3_000 });
        const audio = (index: number) => ({ id: `audio-${index}`, name: `${index}.mp3`, type: "audio/mpeg", url: `blob:audio-${index}`, bytes: 10, durationMs: 1_000 });
        expect(validateJimeng933VideoInput({ ...validInput, images: Array.from({ length: 10 }, (_, index) => image(index)) })).toContain("最多支持 9 张图片");
        expect(validateJimeng933VideoInput({ ...validInput, images: Array.from({ length: 7 }, (_, index) => image(index)), videos: Array.from({ length: 3 }, (_, index) => video(index)), audios: Array.from({ length: 3 }, (_, index) => audio(index)) })).toContain("合计最多支持 12 个素材");
    });

    test("音频不能单独提交", () => {
        expect(validateJimeng933VideoInput({ ...validInput, audios: [{ id: "audio", name: "audio.wav", type: "audio/wav", url: "blob:audio", bytes: 10, durationMs: 5_000 }] })).toContain("不能单独使用");
    });

    test("使用十进制素材大小上限", () => {
        const image = { id: "image", name: "image.png", type: "image/png", dataUrl: "blob:image", bytes: 30_000_001 };
        const videos = [
            { id: "video-1", name: "1.mp4", type: "video/mp4", url: "blob:1", bytes: 25_000_001, width: 1280, height: 720, durationMs: 5_000 },
            { id: "video-2", name: "2.mov", type: "video/quicktime", url: "blob:2", bytes: 25_000_000, width: 720, height: 480, durationMs: 5_000 },
        ];
        expect(validateJimeng933VideoInput({ ...validInput, images: [image] })).toContain("30,000,000");
        expect(validateJimeng933VideoInput({ ...validInput, videos })).toContain("50,000,000");
    });

    test("限制视频尺寸与素材总时长", () => {
        const video = { id: "video", name: "video.mp4", type: "video/mp4", url: "blob:video", bytes: 10, width: 1920, height: 1080, durationMs: 16_000 };
        expect(validateJimeng933VideoInput({ ...validInput, videos: [video] })).toContain("尺寸不符合要求");
        expect(validateJimeng933VideoInput({ ...validInput, videos: [{ ...video, width: 1280, height: 720 }] })).toContain("2–15 秒");
    });
});
