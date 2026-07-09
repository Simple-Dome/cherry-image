function normalizeBasePath(value: string | undefined) {
    const trimmed = (value || "").trim();
    if (!trimmed || trimmed === "/") return "";
    return `/${trimmed.replace(/^\/+|\/+$/g, "")}`;
}

export const APP_BASE_PATH = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH);

export function withBasePath(path: string) {
    if (/^[a-z][a-z0-9+.-]*:/i.test(path)) return path;
    const normalizedPath = path.startsWith("/") ? path : `/${path}`;
    return `${APP_BASE_PATH}${normalizedPath}`;
}
