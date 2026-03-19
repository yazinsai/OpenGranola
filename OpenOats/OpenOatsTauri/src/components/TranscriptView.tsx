import { useEffect, useRef } from "react";
import { Utterance } from "../types";

interface Props {
  utterances: Utterance[];
}

export function TranscriptView({ utterances }: Props) {
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [utterances.length]);

  if (utterances.length === 0) {
    return (
      <div style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", color: "#666", fontSize: 14 }}>
        Transcript will appear here when recording starts
      </div>
    );
  }

  return (
    <div style={{ flex: 1, overflowY: "auto", padding: "12px 16px" }}>
      {utterances.map((u) => (
        <div key={u.id} style={{ marginBottom: 10 }}>
          <span style={{
            fontSize: 11,
            fontWeight: 600,
            color: u.speaker === "you" ? "#3498db" : "#e67e22",
            marginRight: 8,
            textTransform: "uppercase",
          }}>
            {u.speaker === "you" ? "You" : "Them"}
          </span>
          <span style={{ fontSize: 14, color: "#ddd" }}>{u.text}</span>
          <span style={{ fontSize: 10, color: "#555", marginLeft: 8 }}>
            {new Date(u.timestamp).toLocaleTimeString()}
          </span>
        </div>
      ))}
      <div ref={bottomRef} />
    </div>
  );
}
