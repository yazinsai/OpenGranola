import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AppSettings } from "../types";

export function SettingsView() {
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    invoke<AppSettings>("get_settings").then(setSettings);
  }, []);

  if (!settings) return <div style={{ padding: 16, color: "#666" }}>Loading settings…</div>;

  const save = async (updated: AppSettings) => {
    await invoke("save_settings", { newSettings: updated });
    setSettings(updated);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const field = (label: string, value: string, key: keyof AppSettings, type = "text") => (
    <div style={{ marginBottom: 12 }}>
      <label style={{ display: "block", fontSize: 12, color: "#888", marginBottom: 4 }}>{label}</label>
      <input
        type={type}
        value={value}
        onChange={(e) => save({ ...settings, [key]: e.target.value })}
        style={{ width: "100%", padding: "4px 8px", background: "#1a1a1a", color: "#fff", border: "1px solid #444", borderRadius: 4, fontSize: 13, boxSizing: "border-box" }}
      />
    </div>
  );

  return (
    <div style={{ padding: 16, overflowY: "auto", height: "100%" }}>
      <h3 style={{ margin: "0 0 16px", color: "#ccc" }}>Settings</h3>

      <section style={{ marginBottom: 20 }}>
        <h4 style={{ color: "#888", fontSize: 12, textTransform: "uppercase", margin: "0 0 8px" }}>LLM</h4>
        {field("Model", settings.selectedModel, "selectedModel")}
        {field("Ollama LLM Model", settings.ollamaLlmModel, "ollamaLlmModel")}
      </section>

      <section style={{ marginBottom: 20 }}>
        <h4 style={{ color: "#888", fontSize: 12, textTransform: "uppercase", margin: "0 0 8px" }}>Embeddings</h4>
        {field("Ollama Embed Model", settings.ollamaEmbedModel, "ollamaEmbedModel")}
        {field("Ollama Base URL", settings.ollamaBaseUrl, "ollamaBaseUrl")}
        {field("OpenAI Embed Base URL", settings.openAiEmbedBaseUrl, "openAiEmbedBaseUrl")}
      </section>

      <section style={{ marginBottom: 20 }}>
        <h4 style={{ color: "#888", fontSize: 12, textTransform: "uppercase", margin: "0 0 8px" }}>Transcription</h4>
        {field("Locale (e.g. en-US)", settings.transcriptionLocale, "transcriptionLocale")}
      </section>

      <section style={{ marginBottom: 20 }}>
        <h4 style={{ color: "#888", fontSize: 12, textTransform: "uppercase", margin: "0 0 8px" }}>Knowledge Base</h4>
        {field("KB Folder Path", settings.kbFolderPath ?? "", "kbFolderPath")}
        {field("Notes Folder Path", settings.notesFolderPath, "notesFolderPath")}
      </section>

      {saved && <div style={{ color: "#27ae60", fontSize: 13 }}>✓ Saved</div>}
    </div>
  );
}
