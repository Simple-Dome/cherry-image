export const CANVAS_IMAGE_QUALITY = "high";

export const IMAGE_SIZE_TIERS = ["1K", "2K", "4K"] as const;
export type ImageSizeTier = (typeof IMAGE_SIZE_TIERS)[number];

export const IMAGE_ASPECT_RATIOS = ["1:1", "3:2", "2:3", "16:9", "9:16", "4:3", "3:4", "21:9"] as const;
export type ImageAspectRatio = (typeof IMAGE_ASPECT_RATIOS)[number];

export const IMAGE_SIZE_PRESETS: Record<ImageSizeTier, Record<ImageAspectRatio, string>> = {
    "1K": {
        "1:1": "1024x1024",
        "3:2": "1536x1024",
        "2:3": "1024x1536",
        "16:9": "1280x720",
        "9:16": "720x1280",
        "4:3": "1024x768",
        "3:4": "768x1024",
        "21:9": "1280x544",
    },
    "2K": {
        "1:1": "2048x2048",
        "3:2": "2160x1440",
        "2:3": "1440x2160",
        "16:9": "2560x1440",
        "9:16": "1440x2560",
        "4:3": "2048x1536",
        "3:4": "1536x2048",
        "21:9": "2560x1088",
    },
    "4K": {
        "1:1": "2880x2880",
        "3:2": "3456x2304",
        "2:3": "2304x3456",
        "16:9": "3840x2160",
        "9:16": "2160x3840",
        "4:3": "3200x2400",
        "3:4": "2400x3200",
        "21:9": "3840x1600",
    },
};

const LEGACY_QUALITY_BASE: Record<string, number> = {
    low: 1024,
    standard: 1024,
    medium: 2048,
    hd: 2048,
    high: 2880,
};
const IMAGE_SIZE_STEP = 16;
const DEFAULT_IMAGE_SHORT_SIDE = 1024;

export type ImageSizePresetSelection = {
    tier: ImageSizeTier;
    ratio: ImageAspectRatio;
};

export function resolveImagePresetSize(tier: ImageSizeTier, ratio: ImageAspectRatio) {
    return IMAGE_SIZE_PRESETS[tier][ratio];
}

export function findImageSizePreset(size: string): ImageSizePresetSelection | null {
    const normalized = size.trim().toLowerCase();
    for (const tier of IMAGE_SIZE_TIERS) {
        for (const ratio of IMAGE_ASPECT_RATIOS) {
            if (IMAGE_SIZE_PRESETS[tier][ratio].toLowerCase() === normalized) return { tier, ratio };
        }
    }
    return null;
}

export function findLegacyImageSizeSelection(size: string, quality: string): ImageSizePresetSelection | null {
    if (!size.trim() || size.trim().toLowerCase() === "auto") return { tier: "1K", ratio: "1:1" };
    const ratio = normalizeAspectRatio(size);
    if (!ratio) return findImageSizePreset(size);
    return { tier: imageSizeTierFromLegacyQuality(quality), ratio };
}

export function resolveCanvasImageRequestSize(size: string, legacyQuality: string) {
    const value = size.trim();
    if (/^\d+x\d+$/i.test(value)) return value.toLowerCase();
    const ratio = normalizeAspectRatio(value);
    if (!ratio) return value && value.toLowerCase() !== "auto" ? value : IMAGE_SIZE_PRESETS["1K"]["1:1"];
    return resolveLegacyRatioSize(ratio, legacyQuality);
}

export function imageSizePresetSummary(size: string, legacyQuality: string) {
    const selection = findImageSizePreset(size) || findLegacyImageSizeSelection(size, legacyQuality);
    return selection ? `${selection.tier} · ${selection.ratio}` : `自定义 · ${size}`;
}

function imageSizeTierFromLegacyQuality(quality: string): ImageSizeTier {
    const value = quality.trim().toLowerCase();
    if (value === "high" || value === "4k") return "4K";
    if (value === "medium" || value === "hd" || value === "2k") return "2K";
    return "1K";
}

function normalizeAspectRatio(value: string): ImageAspectRatio | null {
    const normalized = value.trim() as ImageAspectRatio;
    return IMAGE_ASPECT_RATIOS.includes(normalized) ? normalized : null;
}

function resolveLegacyRatioSize(ratio: ImageAspectRatio, quality: string) {
    const [ratioWidth, ratioHeight] = ratio.split(":").map(Number);
    const normalizedQuality = quality.trim().toLowerCase();
    const qualityAlias = normalizedQuality === "1k" ? "low" : normalizedQuality === "2k" ? "medium" : normalizedQuality === "4k" ? "high" : normalizedQuality;
    const basePixels = LEGACY_QUALITY_BASE[qualityAlias];
    const isLandscape = ratioWidth >= ratioHeight;
    const longRatio = isLandscape ? ratioWidth / ratioHeight : ratioHeight / ratioWidth;
    let longSide: number;
    let shortSide: number;

    if (basePixels) {
        const targetPixels = basePixels * basePixels;
        longSide = Math.floor(Math.sqrt(targetPixels * longRatio) / IMAGE_SIZE_STEP) * IMAGE_SIZE_STEP;
        shortSide = Math.round(longSide / longRatio / IMAGE_SIZE_STEP) * IMAGE_SIZE_STEP;
    } else {
        shortSide = DEFAULT_IMAGE_SHORT_SIDE;
        longSide = Math.round((shortSide * longRatio) / IMAGE_SIZE_STEP) * IMAGE_SIZE_STEP;
    }

    const width = isLandscape ? longSide : shortSide;
    const height = isLandscape ? shortSide : longSide;
    return `${width}x${height}`;
}
