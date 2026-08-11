import { useState } from "react";
import { Clapperboard, GripVertical, Plus, Trash2 } from "lucide-react";
import { Segmented } from "antd";

import type { CanvasTheme } from "@/lib/canvas-theme";
import type { CanvasNodeData, CanvasNodeMetadata, CanvasStoryboardShot } from "@/types/canvas";

export function CanvasStoryboardNode({ node, theme, onChange }: { node: CanvasNodeData; theme: CanvasTheme; onChange: (nodeId: string, patch: Partial<CanvasNodeMetadata>) => void }) {
    const shots = node.metadata?.storyboardShots || [];
    const orderMode = node.metadata?.storyboardOrderMode || "list";
    const [draggedId, setDraggedId] = useState<string | null>(null);
    const total = shots.reduce((sum, shot) => sum + (Number(shot.duration) || 0), 0);

    const update = (next: CanvasStoryboardShot[]) => onChange(node.id, { storyboardShots: next.map((shot, index) => ({ ...shot, ...(orderMode === "list" ? { order: index + 1 } : {}) })) });
    const patchShot = (id: string, patch: Partial<CanvasStoryboardShot>) => update(shots.map((shot) => (shot.id === id ? { ...shot, ...patch } : shot)));

    return (
        <div className="flex h-full w-full cursor-grab flex-col px-4 pb-3 pt-4 active:cursor-grabbing" style={{ color: theme.node.text }} onWheel={(event) => event.stopPropagation()}>
            <div className="flex cursor-grab items-center gap-2 border-b pb-3 active:cursor-grabbing" style={{ borderColor: theme.node.stroke }}>
                <Clapperboard className="size-4" style={{ color: theme.frame.first }} />
                <span className="text-sm font-semibold">分镜脚本</span>
                <span className="ml-auto text-xs" style={{ color: theme.node.muted }}>{shots.length} 镜 · {total} 秒</span>
            </div>

            <div className="mt-2 flex items-center justify-between gap-2">
                <Segmented
                    className="cursor-pointer"
                    size="small"
                    value={orderMode}
                    options={[{ label: "按列表顺序", value: "list" }, { label: "指定序号", value: "custom" }]}
                    onMouseDown={(event) => event.stopPropagation()}
                    onChange={(value) => onChange(node.id, { storyboardOrderMode: value as "list" | "custom" })}
                />
                <button
                    type="button"
                    className="inline-flex h-7 cursor-pointer items-center gap-1 rounded-md px-2 text-xs transition hover:bg-black/5 disabled:opacity-35 dark:hover:bg-white/10"
                    disabled={shots.length >= 15}
                    onMouseDown={(event) => event.stopPropagation()}
                    onClick={() => update([...shots, { id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, prompt: "", duration: 3, order: shots.length + 1 }])}
                >
                    <Plus className="size-3.5" /> 添加镜头
                </button>
            </div>

            <div className="thin-scrollbar mt-2 min-h-0 flex-1 overflow-y-auto pr-1">
                {shots.map((shot, index) => (
                    <div
                        key={shot.id}
                        draggable
                        className="grid cursor-default grid-cols-[20px_34px_minmax(0,1fr)_64px_28px] items-start gap-1.5 border-b py-2"
                        style={{ borderColor: theme.node.stroke, opacity: draggedId === shot.id ? 0.45 : 1 }}
                        onMouseDown={(event) => event.stopPropagation()}
                        onDragStart={() => setDraggedId(shot.id)}
                        onDragEnd={() => setDraggedId(null)}
                        onDragOver={(event) => event.preventDefault()}
                        onDrop={() => {
                            if (!draggedId || draggedId === shot.id) return;
                            const from = shots.findIndex((item) => item.id === draggedId);
                            const to = shots.findIndex((item) => item.id === shot.id);
                            const next = [...shots];
                            next.splice(to, 0, next.splice(from, 1)[0]);
                            update(next);
                            setDraggedId(null);
                        }}
                    >
                        <GripVertical className="mt-2 size-4 cursor-grab" style={{ color: theme.node.faint }} />
                        {orderMode === "custom" ? (
                            <input
                                type="number"
                                min={1}
                                className="h-8 w-full cursor-text rounded-md border bg-transparent px-1 text-center text-xs outline-none"
                                style={{ borderColor: theme.node.stroke }}
                                value={shot.order || ""}
                                onChange={(event) => patchShot(shot.id, { order: Number(event.target.value) || undefined })}
                                aria-label={`镜头 ${index + 1} 序号`}
                            />
                        ) : <span className="pt-2 text-center text-xs font-medium" style={{ color: theme.node.muted }}>{index + 1}</span>}
                        <textarea
                            value={shot.prompt}
                            rows={2}
                            className="min-h-8 cursor-text resize-none rounded-md border bg-transparent px-2 py-1.5 text-xs leading-4 outline-none"
                            style={{ borderColor: theme.node.stroke, color: theme.node.text }}
                            placeholder={`镜头 ${index + 1} 的画面与动作`}
                            onChange={(event) => patchShot(shot.id, { prompt: event.target.value })}
                        />
                        <label className="relative block">
                            <input
                                type="number"
                                min={1}
                                className="h-8 w-full cursor-text rounded-md border bg-transparent pl-2 pr-5 text-xs outline-none"
                                style={{ borderColor: theme.node.stroke }}
                                value={shot.duration}
                                onChange={(event) => patchShot(shot.id, { duration: Math.max(1, Number(event.target.value) || 1) })}
                                aria-label={`镜头 ${index + 1} 时长`}
                            />
                            <span className="pointer-events-none absolute right-1.5 top-2 text-[10px]" style={{ color: theme.node.faint }}>秒</span>
                        </label>
                        <button type="button" className="grid size-8 cursor-pointer place-items-center rounded-md transition hover:bg-black/5 disabled:opacity-25 dark:hover:bg-white/10" disabled={shots.length <= 2} onClick={() => update(shots.filter((item) => item.id !== shot.id))} aria-label={`删除镜头 ${index + 1}`}>
                            <Trash2 className="size-3.5" />
                        </button>
                    </div>
                ))}
            </div>
        </div>
    );
}
