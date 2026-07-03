export const VIDEO_REFERENCE_IMAGE_MAX_EDGE = 1024;
export const VIDEO_REFERENCE_IMAGE_JPEG_QUALITY = 0.82;

export type VideoReferenceImageInfo = {
    width: number;
    height: number;
    mimeType?: string;
};

export type VideoReferenceImageSize = {
    width: number;
    height: number;
    wasResized: boolean;
};

export type VideoReferenceImageOptimization = {
    dataUrl: string;
    optimized: boolean;
    originalWidth: number;
    originalHeight: number;
    width: number;
    height: number;
    originalMimeType: string;
};

export function calculateVideoReferenceImageSize(width: number, height: number, maxEdge = VIDEO_REFERENCE_IMAGE_MAX_EDGE): VideoReferenceImageSize {
    const longestEdge = Math.max(width, height);
    if (!width || !height || longestEdge <= maxEdge) return { width, height, wasResized: false };
    const scale = maxEdge / longestEdge;
    return {
        width: Math.max(1, Math.round(width * scale)),
        height: Math.max(1, Math.round(height * scale)),
        wasResized: true,
    };
}

export function shouldOptimizeVideoReferenceImage(info: VideoReferenceImageInfo, maxEdge = VIDEO_REFERENCE_IMAGE_MAX_EDGE) {
    const isJpeg = /^image\/jpe?g$/i.test(info.mimeType || "");
    return !isJpeg || Math.max(info.width, info.height) > maxEdge;
}

export async function optimizeVideoReferenceImageDataUrl(dataUrl: string): Promise<VideoReferenceImageOptimization> {
    const image = await loadImage(dataUrl);
    const originalMimeType = dataUrlMimeType(dataUrl) || "image/png";
    const size = calculateVideoReferenceImageSize(image.naturalWidth || image.width, image.naturalHeight || image.height);
    const shouldOptimize = shouldOptimizeVideoReferenceImage({
        width: image.naturalWidth || image.width,
        height: image.naturalHeight || image.height,
        mimeType: originalMimeType,
    });

    if (!shouldOptimize) {
        return {
            dataUrl,
            optimized: false,
            originalWidth: image.naturalWidth || image.width,
            originalHeight: image.naturalHeight || image.height,
            width: size.width,
            height: size.height,
            originalMimeType,
        };
    }

    const canvas = document.createElement("canvas");
    canvas.width = size.width;
    canvas.height = size.height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("当前浏览器不支持 Canvas");
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, size.width, size.height);
    ctx.drawImage(image, 0, 0, size.width, size.height);

    return {
        dataUrl: await canvasToDataUrl(canvas, "image/jpeg", VIDEO_REFERENCE_IMAGE_JPEG_QUALITY),
        optimized: true,
        originalWidth: image.naturalWidth || image.width,
        originalHeight: image.naturalHeight || image.height,
        width: size.width,
        height: size.height,
        originalMimeType,
    };
}

function dataUrlMimeType(dataUrl: string) {
    const match = dataUrl.match(/^data:([^;,]+)[;,]/i);
    return match?.[1] || "";
}

function loadImage(src: string) {
    return new Promise<HTMLImageElement>((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error("参考图读取失败，请换一张图片或重新上传"));
        image.src = src;
    });
}

function canvasToDataUrl(canvas: HTMLCanvasElement, mimeType: string, quality: number) {
    return new Promise<string>((resolve, reject) => {
        canvas.toBlob(
            (blob) => {
                if (!blob) {
                    reject(new Error("参考图压缩失败，请换一张图片或重新上传"));
                    return;
                }
                const reader = new FileReader();
                reader.onload = () => resolve(String(reader.result || ""));
                reader.onerror = () => reject(new Error("参考图压缩失败，请换一张图片或重新上传"));
                reader.readAsDataURL(blob);
            },
            mimeType,
            quality,
        );
    });
}
