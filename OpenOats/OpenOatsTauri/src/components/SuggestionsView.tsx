import { useState } from "react";
import { Suggestion } from "../types";

interface Props {
  suggestions: Suggestion[];
  onFeedback?: (id: string, helpful: boolean) => void;
}

export function SuggestionsView({ suggestions, onFeedback }: Props) {
  const [dismissed, setDismissed] = useState<Set<string>>(new Set());

  if (suggestions.length === 0) {
    return (
      <div style={{ padding: 16, color: "#666", fontSize: 13 }}>
        Suggestions will appear here during recording
      </div>
    );
  }

  const visible = suggestions.filter((s) => !dismissed.has(s.id));

  return (
    <div style={{ overflowY: "auto", padding: "8px 12px" }}>
      {visible.map((s) => (
        <div key={s.id} style={{
          background: "#1e2a3a",
          border: "1px solid #2c4a6e",
          borderRadius: 8,
          padding: 12,
          marginBottom: 8,
        }}>
          <p style={{ margin: "0 0 8px", fontSize: 14, color: "#e0e8f0", lineHeight: 1.5 }}>{s.text}</p>
          {s.kbHits?.length > 0 && (
            <div style={{ fontSize: 11, color: "#5882a6", marginBottom: 8 }}>
              {s.kbHits.map((h) => (
                <span key={h.id} style={{ marginRight: 8 }}>📄 {h.sourceFile}</span>
              ))}
            </div>
          )}
          <div style={{ display: "flex", gap: 6 }}>
            <button
              onClick={() => { onFeedback?.(s.id, true); setDismissed((p) => new Set([...p, s.id])); }}
              style={{ fontSize: 11, padding: "2px 8px", background: "#27ae60", color: "#fff", border: "none", borderRadius: 3, cursor: "pointer" }}
            >👍 Helpful</button>
            <button
              onClick={() => { onFeedback?.(s.id, false); setDismissed((p) => new Set([...p, s.id])); }}
              style={{ fontSize: 11, padding: "2px 8px", background: "#555", color: "#fff", border: "none", borderRadius: 3, cursor: "pointer" }}
            >👎 Not helpful</button>
            <button
              onClick={() => setDismissed((p) => new Set([...p, s.id]))}
              style={{ fontSize: 11, padding: "2px 8px", background: "transparent", color: "#888", border: "1px solid #444", borderRadius: 3, cursor: "pointer" }}
            >✕</button>
          </div>
        </div>
      ))}
    </div>
  );
}
