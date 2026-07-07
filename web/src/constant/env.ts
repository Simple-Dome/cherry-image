export const APP_VERSION = process.env.NEXT_PUBLIC_APP_VERSION || "dev";

export const DOCS_URL = process.env.NEXT_PUBLIC_DOC_URL || "https://docs.canvas.best";

export const UPLOAD_BASE = (process.env.VITE_UPLOAD_BASE || process.env.NEXT_PUBLIC_UPLOAD_BASE || "").replace(/\/+$/, "");
