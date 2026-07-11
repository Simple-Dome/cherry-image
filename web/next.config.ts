import type { NextConfig } from "next";
import { PHASE_DEVELOPMENT_SERVER } from "next/constants";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { parseChangelog } from "@/lib/release";

const webDir = dirname(fileURLToPath(import.meta.url));
const localVersion = readFileSync(resolve(webDir, "../VERSION"), "utf8").trim() || "dev";
const localChangelog = readFileSync(resolve(webDir, "../CHANGELOG.md"), "utf8");
const basePath = normalizeBasePath(process.env.NEXT_BASE_PATH);

export const appHtmlNoStoreHeaders = [
    {
        source: "/:path((?!_next/static|_next/image|favicon.ico|.*\\..*).*)",
        headers: [
            { key: "Cache-Control", value: "no-store, no-cache, must-revalidate, proxy-revalidate" },
            { key: "Pragma", value: "no-cache" },
            { key: "Expires", value: "0" },
        ],
    },
];

function normalizeBasePath(value: string | undefined) {
    const trimmed = (value || "").trim();
    if (!trimmed || trimmed === "/") return "";
    return `/${trimmed.replace(/^\/+|\/+$/g, "")}`;
}

export default function nextConfig(phase: string): NextConfig {
    const isDev = phase === PHASE_DEVELOPMENT_SERVER;
    const releases = parseChangelog(localChangelog);

    return {
        output: "standalone",
        outputFileTracingRoot: webDir,
        ...(basePath ? { basePath } : {}),
        turbopack: {
            root: webDir,
        },
        allowedDevOrigins: isDev ? ["*.*.*.*"] : [],
        typescript: {
            ignoreBuildErrors: true,
        },
        env: {
            NEXT_PUBLIC_APP_VERSION: localVersion,
            NEXT_PUBLIC_APP_RELEASES: JSON.stringify(releases),
            NEXT_PUBLIC_BASE_PATH: basePath,
        },
        async headers() {
            return appHtmlNoStoreHeaders;
        },
    };
}
