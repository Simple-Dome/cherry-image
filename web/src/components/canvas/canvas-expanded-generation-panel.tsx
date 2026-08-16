import { useEffect, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Minimize2 } from "lucide-react";
import { Button, Tooltip } from "antd";

import { canvasThemes } from "@/lib/canvas-theme";
import { useThemeStore } from "@/stores/use-theme-store";

export function CanvasExpandedGenerationPanel({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
    const theme = canvasThemes[useThemeStore((state) => state.theme)];

    useEffect(() => {
        const closeOnEscape = (event: KeyboardEvent) => {
            if (event.key !== "Escape" || event.defaultPrevented) return;
            event.preventDefault();
            onClose();
        };
        window.addEventListener("keydown", closeOnEscape);
        return () => window.removeEventListener("keydown", closeOnEscape);
    }, [onClose]);

    return createPortal(
        <div
            data-canvas-no-zoom
            role="dialog"
            aria-modal="true"
            aria-label={`${title}展开编辑`}
            className="fixed inset-6 z-[1000] min-h-0 rounded-3xl border p-5 shadow-2xl backdrop-blur-xl"
            style={{ background: theme.toolbar.panel, borderColor: theme.toolbar.border, color: theme.node.text }}
            onMouseDown={(event) => event.stopPropagation()}
            onPointerDown={(event) => event.stopPropagation()}
            onWheel={(event) => event.stopPropagation()}
        >
            <Tooltip title="收起编辑面板">
                <Button type="text" className="!absolute !right-4 !top-4 !z-20 !grid !size-9 !min-w-9 !place-items-center !rounded-lg !p-0" icon={<Minimize2 className="size-4" />} onClick={onClose} aria-label="收起编辑面板" />
            </Tooltip>
            <div className="h-full min-h-0">{children}</div>
        </div>,
        document.body,
    );
}
