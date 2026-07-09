import { describe, expect, test } from "bun:test";

import { appHtmlNoStoreHeaders } from "./next.config";

describe("Next cache headers", () => {
    test("disables shared caching for app HTML pages without touching static assets", () => {
        expect(appHtmlNoStoreHeaders).toEqual([
            {
                source: "/:path((?!_next/static|_next/image|favicon.ico|.*\\..*).*)",
                headers: [
                    { key: "Cache-Control", value: "no-store, no-cache, must-revalidate, proxy-revalidate" },
                    { key: "Pragma", value: "no-cache" },
                    { key: "Expires", value: "0" },
                ],
            },
        ]);
    });
});
