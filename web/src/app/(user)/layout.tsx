"use client";

import { Suspense, type ReactNode } from "react";

import { AppTopNav } from "@/components/layout/app-top-nav";

export default function UserLayout({ children }: { children: ReactNode }) {
    return (
        <div className="flex h-dvh flex-col overflow-hidden bg-background text-foreground">
            <AppTopNav />
            <div className="min-h-0 flex-1 overflow-hidden">
                <Suspense fallback={<main className="flex h-full items-center justify-center bg-background text-sm text-stone-500">正在加载...</main>}>{children}</Suspense>
            </div>
        </div>
    );
}
