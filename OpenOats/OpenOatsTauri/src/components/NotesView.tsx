import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

const TEMPLATES = [
  { id: "00000000-0000-0000-0000-000000000000", name: "Generic" },
  { id: "00000000-0000-0000-0000-000000000001", name: "1:1" },
  { id: "00000000-0000-0000-0000-000000000002", name: "Customer Discovery" },
  { id: "00000000-0000-0000-0000-000000000003", name: "Hiring" },
  { id: "00000000-0000-0000-0000-000000000004", name: "Stand-Up" },
  { id: "00000000-0000-0000-0000-000000000005", name: "Weekly Meeting" },
];

interface Props {
  sessionId?: string;
}

export function NotesView({ sessionId }: Props) {
  const [selectedTemplate, setSelectedTemplate] = useState(TEMPLATES[0].id);
  const [markdown, setMarkdown] = useState("");
  const [isGenerating, setIsGenerating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const unlisten = listen<string>("notes-chunk", (e) => {
      setMarkdown((prev) => prev + e.payload);
    });
    return () => { unlisten.then((f) => f()); };
  }, []);

  const handleGenerate = async () => {
    if (!sessionId) return;
    setMarkdown("");
    setIsGenerating(true);
    setError(null);
    try {
      await invoke("generate_notes", { sessionId, templateId: selectedTemplate });
    } catch (e) {
      setError(String(e));
    } finally {
      setIsGenerating(false);
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", padding: 16 }}>
      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <select
          value={selectedTemplate}
          onChange={(e) => setSelectedTemplate(e.target.value)}
          style={{ flex: 1, padding: "4px 8px", background: "#1a1a1a", color: "#fff", border: "1px solid #444", borderRadius: 4 }}
        >
          {TEMPLATES.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
        </select>
        <button
          onClick={handleGenerate}
          disabled={isGenerating || !sessionId}
          style={{
            padding: "4px 16px",
            background: "#8e44ad",
            color: "#fff",
            border: "none",
            borderRadius: 4,
            cursor: isGenerating || !sessionId ? "not-allowed" : "pointer",
            opacity: isGenerating || !sessionId ? 0.5 : 1,
          }}
        >
          {isGenerating ? "Generating…" : "Generate Notes"}
        </button>
      </div>

      {error && <div style={{ color: "#e74c3c", fontSize: 13, marginBottom: 8 }}>{error}</div>}

      {markdown ? (
        <pre style={{ flex: 1, overflowY: "auto", fontSize: 13, color: "#ddd", whiteSpace: "pre-wrap", lineHeight: 1.6 }}>
          {markdown}
        </pre>
      ) : (
        <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", color: "#666", fontSize: 14 }}>
          {sessionId ? "Select a template and click Generate Notes" : "Start a session to generate notes"}
        </div>
      )}
    </div>
  );
}
