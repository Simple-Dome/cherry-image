import { useMemo, useState } from "react";
import { Image, Tooltip } from "antd";

import type { NodeGenerationInput } from "./canvas-node-generation";

export function CanvasReferenceThumbnailStrip({ inputs, expanded = false }: { inputs: NodeGenerationInput[]; expanded?: boolean }) {
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);
    const images = useMemo(() => inputs.filter((input) => input.type === "image" && Boolean(input.image?.dataUrl)), [inputs]);
    if (!images.length) return null;

    return (
        <div className={`thin-scrollbar flex shrink-0 items-center gap-2 overflow-x-auto pr-12 ${expanded ? "mb-3 min-h-20" : "mb-2 min-h-12"}`} aria-label={`已连接 ${images.length} 张参考图片`}>
            {images.map((input, index) => (
                <Tooltip key={input.nodeId} title={`${index + 1}. ${input.title}`}>
                    <button type="button" className={`relative shrink-0 overflow-hidden rounded-lg outline-none transition hover:opacity-85 focus-visible:ring-2 ${expanded ? "size-20" : "size-12"}`} onClick={() => setPreviewUrl(input.image?.dataUrl || null)} aria-label={`预览参考图片 ${index + 1}`}>
                        <img src={input.image?.dataUrl} alt={input.title} className="h-full w-full object-cover" />
                        <span className="absolute left-1 top-1 grid size-5 place-items-center rounded-full bg-black/65 text-[10px] font-semibold text-white">{index + 1}</span>
                    </button>
                </Tooltip>
            ))}
            {previewUrl ? <Image src={previewUrl} alt="参考图片预览" style={{ display: "none" }} preview={{ open: true, src: previewUrl, zIndex: 1400, onOpenChange: (open) => !open && setPreviewUrl(null) }} /> : null}
        </div>
    );
}
