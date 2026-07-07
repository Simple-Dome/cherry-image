import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type SignUploadRequest = {
    name?: string;
    contentType?: string;
    size?: number;
    kind?: "video" | "audio";
};

const maxBytes = Number(process.env.UPLOAD_MAX_BYTES || 500 * 1024 * 1024);
const expiresIn = Number(process.env.UPLOAD_PRESIGN_EXPIRES_SECONDS || 900);
const bucket = process.env.UPLOAD_STORAGE_BUCKET || "";
const publicBase = (process.env.UPLOAD_PUBLIC_BASE || "").replace(/\/+$/, "");

const s3 = new S3Client({
    region: process.env.UPLOAD_STORAGE_REGION || "auto",
    endpoint: process.env.UPLOAD_STORAGE_ENDPOINT || undefined,
    forcePathStyle: process.env.UPLOAD_STORAGE_FORCE_PATH_STYLE === "true",
    credentials: {
        accessKeyId: process.env.UPLOAD_STORAGE_ACCESS_KEY_ID || "",
        secretAccessKey: process.env.UPLOAD_STORAGE_SECRET_ACCESS_KEY || "",
    },
});

export async function POST(request: Request) {
    try {
        assertStorageConfig();
        const body = (await request.json()) as SignUploadRequest;
        const contentType = normalizeContentType(body.contentType, body.kind);
        const kind = body.kind || (contentType.startsWith("audio/") ? "audio" : "video");
        const size = Number(body.size || 0);
        if (!Number.isFinite(size) || size <= 0) return Response.json({ error: "文件大小无效" }, { status: 400 });
        if (size > maxBytes) return Response.json({ error: `文件不能超过 ${Math.floor(maxBytes / 1024 / 1024)}MB` }, { status: 400 });

        const key = `${kind}-inputs/${new Date().toISOString().slice(0, 7).replace("-", "/")}/${crypto.randomUUID()}-${safeName(body.name, contentType)}`;
        const headers = { "Content-Type": contentType };
        const uploadUrl = await getSignedUrl(s3, new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: contentType }), { expiresIn });

        return Response.json({ uploadUrl, publicUrl: `${publicBase}/${key}`, headers, expiresIn, retentionDays: 30 });
    } catch (error) {
        return Response.json({ error: error instanceof Error ? error.message : "生成上传地址失败" }, { status: 500 });
    }
}

function assertStorageConfig() {
    if (!bucket || !publicBase || !process.env.UPLOAD_STORAGE_ACCESS_KEY_ID || !process.env.UPLOAD_STORAGE_SECRET_ACCESS_KEY) {
        throw new Error("对象存储未配置完整");
    }
}

function normalizeContentType(value?: string, kind?: "video" | "audio") {
    const contentType = (value || "").split(";")[0].trim().toLowerCase();
    if (contentType.startsWith("video/") || contentType.startsWith("audio/")) return contentType;
    return kind === "audio" ? "audio/mpeg" : "video/mp4";
}

function safeName(name: string | undefined, contentType: string) {
    const fallback = contentType.startsWith("audio/") ? "audio.mp3" : "video.mp4";
    return (name || fallback).split("/").pop()?.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120) || fallback;
}