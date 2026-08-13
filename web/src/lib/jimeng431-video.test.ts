import { describe, expect, test } from "bun:test";

import { normalizeJimeng431Ratio, normalizeJimeng431Resolution, validateJimeng431VideoInput, type Jimeng431VideoValidationInput } from "./jimeng431-video";

const validInput: Jimeng431VideoValidationInput = {
    model: "leonardo-seedance-2.0",
    prompt: "雨后的城市街道",
    duration: 5,
    resolution: "720p",
    aspectRatio: "16:9",
    images: [],
    videos: [],
    audios: [],
};

describe("431 即梦视频参数", () => {
    test("归一化通用清晰度和比例", () => {
        expect(normalizeJimeng431Resolution("480")).toBe("480p");
        expect(normalizeJimeng431Resolution("720")).toBe("720p");
        expect(normalizeJimeng431Ratio("1280x720")).toBe("16:9");
        expect(normalizeJimeng431Ratio("1024x1024")).toBe("1:1");
    });

    test("只接受公开模型、5/10/14 秒、480p/720p 和三个比例", () => {
        expect(validateJimeng431VideoInput(validInput)).toBeNull();
        expect(validateJimeng431VideoInput({ ...validInput, duration: 15 })).toContain("5、10、14");
        expect(validateJimeng431VideoInput({ ...validInput, resolution: "1080p" })).toContain("480p、720p");
        expect(validateJimeng431VideoInput({ ...validInput, aspectRatio: "4:3" })).toContain("16:9、1:1、9:16");
        expect(validateJimeng431VideoInput({ ...validInput, model: "firefly-video-v2" })).toContain("仅支持");
    });

    test("使用无符号 32 位 Seed 范围并拒绝分镜", () => {
        expect(validateJimeng431VideoInput({ ...validInput, seed: 4_294_967_295 })).toBeNull();
        expect(validateJimeng431VideoInput({ ...validInput, seed: 4_294_967_296 })).toContain("Seed");
        expect(validateJimeng431VideoInput({ ...validInput, shots: [{ id: "1", prompt: "镜头一", duration: 5 }] })).toContain("不支持结构化分镜");
    });

    test("分别限制普通图片、首尾帧、视频和音频", () => {
        const image = (index: number) => ({ id: `image-${index}`, name: `${index}.png`, type: "image/png", dataUrl: `blob:${index}`, bytes: 10 });
        expect(validateJimeng431VideoInput({ ...validInput, images: Array.from({ length: 5 }, (_, index) => image(index)) })).toContain("4 张普通参考图片");
        expect(validateJimeng431VideoInput({ ...validInput, images: [image(1), image(2)], imageRoles: { "image-1": "first_frame", "image-2": "first_frame" } })).toContain("一张首帧");
        expect(validateJimeng431VideoInput({ ...validInput, audios: [1, 2].map((index) => ({ id: `${index}`, name: `${index}.mp3`, type: "audio/mpeg", url: `blob:${index}`, bytes: 10 })) })).toContain("1 个参考音频");
    });

    test("校验参考视频的单个时长和尺寸", () => {
        const video = { id: "video", name: "video.mp4", type: "video/mp4", url: "blob:video", bytes: 10, width: 1280, height: 720, durationMs: 3_000 };
        expect(validateJimeng431VideoInput({ ...validInput, videos: [video] })).toBeNull();
        expect(validateJimeng431VideoInput({ ...validInput, videos: [{ ...video, durationMs: 10_001 }] })).toContain("3–10 秒");
        expect(validateJimeng431VideoInput({ ...validInput, videos: [{ ...video, width: 640, height: 360 }] })).toContain("短边至少 720px");
    });
});
