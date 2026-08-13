import { resolveModelRequestConfig, type AiConfig } from "@/stores/use-config-store";
import type { ReferenceImage } from "@/types/image";
import type { ReferenceAudio, ReferenceVideo } from "@/types/media";
import type { VideoImageRole, VideoShot } from "@/lib/jimeng933-video";

export const JIMENG431_VIDEO_MODELS = ["leonardo-seedance-2.0", "leonardo-seedance-2.0-fast"] as const;
export const JIMENG431_DURATION_OPTIONS = [5, 10, 14] as const;
export const JIMENG431_RESOLUTION_OPTIONS = ["480p", "720p"] as const;
export const JIMENG431_RATIO_OPTIONS = ["16:9", "1:1", "9:16"] as const;
export const JIMENG431_REFERENCE_LIMITS = {
    images: 4,
    videos: 3,
    audios: 1,
    total: 10,
    imageMaxBytes: 30_000_000,
    videoTotalMaxBytes: 50_000_000,
    audioMaxBytes: 15_000_000,
    videoMinDurationMs: 3_000,
    videoMaxDurationMs: 10_000,
    audioMaxDurationMs: 15_000,
    videoMinShortEdge: 720,
    videoMaxLongEdge: 2160,
} as const;

export type Jimeng431VideoValidationInput = {
    model: string;
    prompt: string;
    negativePrompt?: string;
    seed?: number;
    duration: number;
    resolution: string;
    aspectRatio: string;
    images: ReferenceImage[];
    videos: ReferenceVideo[];
    audios: ReferenceAudio[];
    imageRoles?: Record<string, VideoImageRole>;
    shots?: VideoShot[];
};

const imageMimeTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const videoMimeTypes = new Set(["video/mp4", "video/quicktime"]);
const audioMimeTypes = new Set(["audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav"]);
const ratioMap: Record<string, string> = {
    "1280x720": "16:9",
    "720x1280": "9:16",
    "1024x1024": "1:1",
};

export function isJimeng431VideoConfig(config: AiConfig | Pick<AiConfig, "model" | "videoModel" | "apiFormat">) {
    const selectedModel = config.model || config.videoModel;
    const requestConfig = "channels" in config && selectedModel.includes("::") ? resolveModelRequestConfig(config, selectedModel) : config;
    return requestConfig.apiFormat === "jimeng431";
}

export function normalizeJimeng431Resolution(value: string) {
    const normalized = String(value || "").trim().toLowerCase();
    if (normalized === "480" || normalized === "480p" || normalized === "low") return "480p";
    if (["720", "720p", "auto", "medium", "high"].includes(normalized)) return "720p";
    return normalized;
}

export function normalizeJimeng431Ratio(value: string) {
    const normalized = String(value || "").trim().toLowerCase().replace(/\s+/g, "");
    return ratioMap[normalized] || normalized;
}

export function validateJimeng431VideoInput(input: Jimeng431VideoValidationInput): string | null {
    if (!JIMENG431_VIDEO_MODELS.includes(input.model as (typeof JIMENG431_VIDEO_MODELS)[number])) return "431 即梦仅支持 leonardo-seedance-2.0 和 leonardo-seedance-2.0-fast 模型";
    if (!input.prompt.trim()) return "请输入视频提示词";
    if (!JIMENG431_DURATION_OPTIONS.includes(input.duration as (typeof JIMENG431_DURATION_OPTIONS)[number])) return `431 即梦只支持 5、10、14 秒视频，当前为 ${input.duration} 秒`;
    if (!JIMENG431_RESOLUTION_OPTIONS.includes(input.resolution as (typeof JIMENG431_RESOLUTION_OPTIONS)[number])) return `431 即梦分辨率只支持 480p、720p，当前为 ${input.resolution || "空"}`;
    if (!JIMENG431_RATIO_OPTIONS.includes(input.aspectRatio as (typeof JIMENG431_RATIO_OPTIONS)[number])) return `431 即梦画面比例只支持 16:9、1:1、9:16，当前为 ${input.aspectRatio || "空"}`;
    if (input.negativePrompt !== undefined) return "431 即梦不支持负面提示词";
    if (input.shots !== undefined) return "431 即梦不支持结构化分镜，请把分镜描述写入提示词";
    if (input.seed !== undefined && (!Number.isInteger(input.seed) || input.seed < 0 || input.seed > 4_294_967_295)) return "431 即梦 Seed 必须是 0–4294967295 的整数";

    let normalImages = 0;
    let firstFrames = 0;
    let lastFrames = 0;
    for (const image of input.images) {
        const role = input.imageRoles?.[image.id];
        if (role === "first_frame") firstFrames += 1;
        else if (role === "last_frame") lastFrames += 1;
        else normalImages += 1;
    }
    if (normalImages > JIMENG431_REFERENCE_LIMITS.images) return "431 即梦最多支持 4 张普通参考图片";
    if (firstFrames > 1) return "431 即梦最多只能设置一张首帧图片";
    if (lastFrames > 1) return "431 即梦最多只能设置一张尾帧图片";
    if (input.videos.length > JIMENG431_REFERENCE_LIMITS.videos) return "431 即梦最多支持 3 个参考视频";
    if (input.audios.length > JIMENG431_REFERENCE_LIMITS.audios) return "431 即梦最多支持 1 个参考音频";
    if (input.images.length + input.videos.length + input.audios.length > JIMENG431_REFERENCE_LIMITS.total) return "431 即梦参考素材合计最多支持 10 个";

    for (let index = 0; index < input.images.length; index += 1) {
        const image = input.images[index];
        if (!imageMimeTypes.has(normalizeMimeType(image.type))) return `图片 ${index + 1} 仅支持 JPEG、PNG、WebP 格式`;
        if (image.bytes !== undefined && (image.bytes <= 0 || image.bytes > JIMENG431_REFERENCE_LIMITS.imageMaxBytes)) return `图片 ${index + 1} 不能超过 30,000,000 字节且不能为空`;
    }

    let videoBytes = 0;
    for (let index = 0; index < input.videos.length; index += 1) {
        const video = input.videos[index];
        if (!videoMimeTypes.has(normalizeMimeType(video.type))) return `视频 ${index + 1} 仅支持 MP4、MOV 格式`;
        if (video.bytes !== undefined && video.bytes <= 0) return `视频 ${index + 1} 是空文件`;
        videoBytes += video.bytes || 0;
        if (video.durationMs && (video.durationMs < JIMENG431_REFERENCE_LIMITS.videoMinDurationMs || video.durationMs > JIMENG431_REFERENCE_LIMITS.videoMaxDurationMs)) return `视频 ${index + 1} 时长需要在 3–10 秒之间`;
        if (video.width && video.height && (Math.min(video.width, video.height) < JIMENG431_REFERENCE_LIMITS.videoMinShortEdge || Math.max(video.width, video.height) > JIMENG431_REFERENCE_LIMITS.videoMaxLongEdge)) return `视频 ${index + 1} 尺寸不符合要求：短边至少 720px，长边不能超过 2160px`;
    }
    if (videoBytes > JIMENG431_REFERENCE_LIMITS.videoTotalMaxBytes) return "431 即梦参考视频合计不能超过 50,000,000 字节";

    for (let index = 0; index < input.audios.length; index += 1) {
        const audio = input.audios[index];
        if (!audioMimeTypes.has(normalizeMimeType(audio.type))) return `音频 ${index + 1} 仅支持 MP3、WAV 格式`;
        if (audio.bytes !== undefined && (audio.bytes <= 0 || audio.bytes > JIMENG431_REFERENCE_LIMITS.audioMaxBytes)) return `音频 ${index + 1} 不能超过 15,000,000 字节且不能为空`;
        if (audio.durationMs && audio.durationMs > JIMENG431_REFERENCE_LIMITS.audioMaxDurationMs) return `音频 ${index + 1} 时长不能超过 15 秒`;
    }
    return null;
}

function normalizeMimeType(value: string) {
    return value.trim().toLowerCase().split(";", 1)[0];
}
