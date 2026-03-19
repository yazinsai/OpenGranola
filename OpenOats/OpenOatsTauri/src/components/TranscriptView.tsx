import { useEffect, useRef } from "react";
import type { Utterance } from "../types";

// Design system
const colors = {
  background: "#111111",
  surface: "#1a1a1a",
  border: "#333333",
  text: "#eeeeee",
  textSecondary: "#888888",
  textMuted: "#666666",
  you: "#5b8cbf",
  them: "#d2994d",
};

const typography = {
  xs: 10,
  sm: 11,
  base: 12,
  md: 13,
  lg: 14,
};

const spacing = {
  1: 4,
  2: 8,
  3: 12,
  4: 16,
};

interface Props {
  utterances: Utterance[];
  volatileYouText?: string;
  volatileThemText?: string;
}

// Format timestamp to relative time or clock time
function formatTimestamp(timestamp: string): string {
  const date = new Date(timestamp);
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

// Group utterances by time buckets for long sessions
function groupByTimeBucket(utterances: Utterance[]): { time: string; items: Utterance[] }[] {
  const buckets: { time: string; items: Utterance[] }[] = [];
  let currentBucket: { time: string; items: Utterance[] } | null = null;

  for (const utterance of utterances) {
    const time = formatTimestamp(utterance.timestamp);
    const hour = time.split(":")[0];

    if (!currentBucket || currentBucket.time.split(":")[0] !== hour) {
      currentBucket = { time, items: [] };
      buckets.push(currentBucket);
    }
    currentBucket.items.push(utterance);
  }

  return buckets;
}

// Utterance bubble component
function UtteranceBubble({ utterance }: { utterance: Utterance }) {
  const isYou = utterance.speaker === "you";

  return (
    <div
      style={{
        display: "flex",
        gap: spacing[2],
        marginBottom: spacing[3],
        alignItems: "flex-start",
      }}
    >
      {/* Speaker label */}
      <div
        style={{
          minWidth: 40,
          textAlign: "right",
          fontSize: typography.sm,
          fontWeight: 600,
          color: isYou ? colors.you : colors.them,
          textTransform: "uppercase",
          letterSpacing: "0.5px",
          paddingTop: 2,
        }}
      >
        {isYou ? "You" : "Them"}
      </div>

      {/* Content */}
      <div style={{ flex: 1 }}>
        <span
          style={{
            fontSize: typography.md,
            color: colors.text,
            lineHeight: 1.5,
          }}
        >
          {utterance.text}
        </span>
        <span
          style={{
            fontSize: typography.xs,
            color: colors.textMuted,
            marginLeft: spacing[2],
          }}
        >
          {formatTimestamp(utterance.timestamp)}
        </span>
      </div>
    </div>
  );
}

// Volatile text indicator (live transcription)
function VolatileIndicator({
  text,
  speaker,
}: {
  text: string;
  speaker: "you" | "them";
}) {
  const isYou = speaker === "you";

  return (
    <div
      style={{
        display: "flex",
        gap: spacing[2],
        marginBottom: spacing[3],
        alignItems: "flex-start",
        opacity: 0.6,
      }}
    >
      <div
        style={{
          minWidth: 40,
          textAlign: "right",
          fontSize: typography.sm,
          fontWeight: 600,
          color: isYou ? colors.you : colors.them,
          textTransform: "uppercase",
          letterSpacing: "0.5px",
          paddingTop: 2,
        }}
      >
        {isYou ? "You" : "Them"}
      </div>
      <div style={{ flex: 1, display: "flex", alignItems: "center", gap: spacing[2] }}>
        <span
          style={{
            fontSize: typography.md,
            color: colors.textSecondary,
            lineHeight: 1.5,
          }}
        >
          {text}
        </span>
        {/* Pulsing indicator */}
        <span
          style={{
            width: 4,
            height: 4,
            borderRadius: "50%",
            background: isYou ? colors.you : colors.them,
            animation: "pulse 1s ease-in-out infinite",
          }}
        />
      </div>
    </div>
  );
}

export function TranscriptView({ utterances, volatileYouText, volatileThemText }: Props) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [utterances.length]);

  // Empty state
  if (utterances.length === 0 && !volatileYouText && !volatileThemText) {
    return (
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          color: colors.textMuted,
          padding: spacing[4],
          textAlign: "center",
        }}
      >
        <div
          style={{
            width: 48,
            height: 48,
            borderRadius: 12,
            background: `${colors.textMuted}15`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 24,
            marginBottom: spacing[3],
          }}
        >
          🎙️
        </div>
        <h4
          style={{
            fontSize: typography.lg,
            fontWeight: 600,
            color: colors.textSecondary,
            margin: `0 0 ${spacing[2]}px`,
          }}
        >
          No transcript yet
        </h4>
        <p
          style={{
            fontSize: typography.md,
            color: colors.textMuted,
            margin: 0,
            maxWidth: 260,
            lineHeight: 1.5,
          }}
        >
          Click Record to start capturing your conversation.
        </p>
      </div>
    );
  }

  const grouped = groupByTimeBucket(utterances);
  const hasVolatile = !!volatileYouText || !!volatileThemText;

  return (
    <div
      ref={scrollRef}
      style={{
        flex: 1,
        overflowY: "auto",
        padding: spacing[4],
        background: colors.background,
      }}
    >
      {/* Time buckets */}
      {grouped.map((bucket, bucketIndex) => (
        <div key={bucket.time}>
          {/* Time header (show if not the first bucket) */}
          {bucketIndex > 0 && (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: spacing[2],
                margin: `${spacing[4]}px 0`,
              }}
            >
              <div style={{ flex: 1, height: 1, background: colors.border }} />
              <span
                style={{
                  fontSize: typography.xs,
                  color: colors.textMuted,
                  textTransform: "uppercase",
                  letterSpacing: "1px",
                }}
              >
                {bucket.time}
              </span>
              <div style={{ flex: 1, height: 1, background: colors.border }} />
            </div>
          )}

          {/* Utterances in this bucket */}
          {bucket.items.map((utterance) => (
            <UtteranceBubble key={utterance.id} utterance={utterance} />
          ))}
        </div>
      ))}

      {/* Volatile/live text */}
      {volatileYouText && <VolatileIndicator text={volatileYouText} speaker="you" />}
      {volatileThemText && <VolatileIndicator text={volatileThemText} speaker="them" />}

      {/* Bottom anchor for auto-scroll */}
      <div ref={bottomRef} />

      {/* Animations */}
      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.5; transform: scale(0.8); }
        }
      `}</style>
    </div>
  );
}
