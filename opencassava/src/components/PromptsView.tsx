import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { MeetingTemplate } from "../types";
import { colors, typography, spacing, radius, styles } from "../theme";

interface EditState {
  id: string | null; // null = new template
  name: string;
  system_prompt: string;
}

export function PromptsView() {
  const [templates, setTemplates] = useState<MeetingTemplate[]>([]);
  const [editState, setEditState] = useState<EditState | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    invoke<MeetingTemplate[]>("list_templates").then(setTemplates);
  };

  useEffect(() => {
    load();
  }, []);

  const startNew = () => {
    setEditState({ id: null, name: "", system_prompt: "" });
    setError(null);
  };

  const startEdit = (t: MeetingTemplate) => {
    setEditState({ id: t.id, name: t.name, system_prompt: t.system_prompt });
    setError(null);
  };

  const cancel = () => {
    setEditState(null);
    setError(null);
  };

  const save = async () => {
    if (!editState) return;
    if (!editState.name.trim()) {
      setError("Name is required.");
      return;
    }
    if (!editState.system_prompt.trim()) {
      setError("Prompt is required.");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      const template: MeetingTemplate = {
        id: editState.id ?? crypto.randomUUID(),
        name: editState.name.trim(),
        icon: "doc.text",
        system_prompt: editState.system_prompt.trim(),
        is_built_in: false,
      };
      await invoke("save_template", { template });
      load();
      setEditState(null);
    } catch (e) {
      setError(String(e));
    } finally {
      setSaving(false);
    }
  };

  const deleteTemplate = async (id: string) => {
    try {
      await invoke("delete_template", { id });
      load();
    } catch (e) {
      setError(String(e));
    }
  };

  const builtIns = templates.filter((t) => t.is_built_in);
  const custom = templates.filter((t) => !t.is_built_in);

  if (editState !== null) {
    return (
      <div style={{ padding: spacing[4], display: "flex", flexDirection: "column", gap: spacing[3], height: "100%", overflowY: "auto" }}>
        <div style={{ display: "flex", alignItems: "center", gap: spacing[2] }}>
          <button onClick={cancel} style={{ ...styles.buttonSecondary, padding: `${spacing[1]}px ${spacing[2]}px` }}>
            ← Back
          </button>
          <h2 style={{ margin: 0, fontSize: typography["2xl"], fontWeight: 700, color: colors.text }}>
            {editState.id === null ? "New Prompt" : "Edit Prompt"}
          </h2>
        </div>

        {error && (
          <div style={{ color: colors.error, fontSize: typography.md }}>{error}</div>
        )}

        <div style={{ display: "flex", flexDirection: "column", gap: spacing[1] }}>
          <label style={{ fontSize: typography.sm, color: colors.textSecondary, fontWeight: 500 }}>Name</label>
          <input
            value={editState.name}
            onChange={(e) => setEditState((s) => s && { ...s, name: e.target.value })}
            placeholder="e.g. Sales Call"
            style={{ ...styles.input }}
          />
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: spacing[1], flex: 1 }}>
          <label style={{ fontSize: typography.sm, color: colors.textSecondary, fontWeight: 500 }}>
            System Prompt
          </label>
          <textarea
            value={editState.system_prompt}
            onChange={(e) => setEditState((s) => s && { ...s, system_prompt: e.target.value })}
            placeholder="You are a meeting notes assistant. Given a transcript..."
            style={{
              ...styles.input,
              flex: 1,
              minHeight: 260,
              resize: "vertical",
              lineHeight: 1.5,
              fontFamily: "monospace",
            }}
          />
        </div>

        <div style={{ display: "flex", gap: spacing[2] }}>
          <button onClick={save} disabled={saving} style={{ ...styles.button, opacity: saving ? 0.6 : 1, cursor: saving ? "not-allowed" : "pointer" }}>
            {saving ? "Saving..." : "Save Prompt"}
          </button>
          <button onClick={cancel} style={styles.buttonSecondary}>
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div style={{ padding: spacing[4], display: "flex", flexDirection: "column", gap: spacing[4], height: "100%", overflowY: "auto" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div>
          <h2 style={{ margin: 0, fontSize: typography["2xl"], fontWeight: 700, color: colors.text }}>Note Prompts</h2>
          <p style={{ margin: `${spacing[1]}px 0 0`, fontSize: typography.sm, color: colors.textMuted }}>
            Customize how notes are generated for different meeting types.
          </p>
        </div>
        <button onClick={startNew} style={styles.button}>
          + New Prompt
        </button>
      </div>

      {error && (
        <div style={{ color: colors.error, fontSize: typography.md }}>{error}</div>
      )}

      {custom.length > 0 && (
        <section>
          <div style={{ fontSize: typography.sm, fontWeight: 600, color: colors.textMuted, textTransform: "uppercase", letterSpacing: "0.08em", marginBottom: spacing[2] }}>
            Custom
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: spacing[2] }}>
            {custom.map((t) => (
              <TemplateCard
                key={t.id}
                template={t}
                onEdit={() => startEdit(t)}
                onDelete={() => deleteTemplate(t.id)}
              />
            ))}
          </div>
        </section>
      )}

      <section>
        <div style={{ fontSize: typography.sm, fontWeight: 600, color: colors.textMuted, textTransform: "uppercase", letterSpacing: "0.08em", marginBottom: spacing[2] }}>
          Built-in
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: spacing[2] }}>
          {builtIns.map((t) => (
            <TemplateCard key={t.id} template={t} />
          ))}
        </div>
      </section>
    </div>
  );
}

function TemplateCard({
  template,
  onEdit,
  onDelete,
}: {
  template: MeetingTemplate;
  onEdit?: () => void;
  onDelete?: () => void;
}) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div
      style={{
        background: colors.surface,
        border: `1px solid ${colors.border}`,
        borderRadius: radius.lg,
        overflow: "hidden",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: spacing[2],
          padding: `${spacing[2]}px ${spacing[3]}px`,
          cursor: "pointer",
        }}
        onClick={() => setExpanded((v) => !v)}
      >
        <div style={{ flex: 1 }}>
          <div style={{ display: "flex", alignItems: "center", gap: spacing[2] }}>
            <span style={{ fontSize: typography.md, fontWeight: 600, color: colors.text }}>{template.name}</span>
            {template.is_built_in && (
              <span
                style={{
                  fontSize: typography.xs,
                  color: colors.textMuted,
                  background: colors.surfaceElevated,
                  border: `1px solid ${colors.border}`,
                  borderRadius: radius.sm,
                  padding: "1px 6px",
                }}
              >
                built-in
              </span>
            )}
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: spacing[1] }}>
          {onEdit && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onEdit();
              }}
              style={{ ...styles.buttonSecondary, padding: `${spacing[1]}px ${spacing[2]}px`, fontSize: typography.sm }}
            >
              Edit
            </button>
          )}
          {onDelete && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onDelete();
              }}
              style={{ ...styles.buttonDanger, padding: `${spacing[1]}px ${spacing[2]}px`, fontSize: typography.sm }}
            >
              Delete
            </button>
          )}
          <span style={{ color: colors.textMuted, fontSize: typography.sm }}>{expanded ? "▲" : "▼"}</span>
        </div>
      </div>
      {expanded && (
        <div
          style={{
            padding: `${spacing[2]}px ${spacing[3]}px ${spacing[3]}px`,
            borderTop: `1px solid ${colors.border}`,
            background: colors.surfaceElevated,
          }}
        >
          <pre
            style={{
              margin: 0,
              whiteSpace: "pre-wrap",
              fontSize: typography.sm,
              color: colors.textSecondary,
              lineHeight: 1.6,
              fontFamily: "monospace",
            }}
          >
            {template.system_prompt}
          </pre>
        </div>
      )}
    </div>
  );
}
