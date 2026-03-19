import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import "./App.css";

interface Utterance {
  id: number;
  text: string;
  speaker: string;
}

type ModelState = "checking" | "missing" | "downloading" | "ready";

let utteranceId = 0;

function App() {
  const [isRunning, setIsRunning] = useState(false);
  const [statusMsg, setStatusMsg] = useState("Checking...");
  const [modelState, setModelState] = useState<ModelState>("checking");
  const [modelPath, setModelPath] = useState("");
  const [downloadPct, setDownloadPct] = useState(0);
  const [utterances, setUtterances] = useState<Utterance[]>([]);
  const bottomRef = useRef<HTMLDivElement>(null);

  // ── On mount: check for the whisper model ─────────────────────────────────
  useEffect(() => {
    (async () => {
      try {
        const [exists, path] = await Promise.all([
          invoke<boolean>("check_model"),
          invoke<string>("get_model_path"),
        ]);
        setModelPath(path);
        if (exists) {
          setModelState("ready");
          setStatusMsg("Ready");
        } else {
          setModelState("missing");
          setStatusMsg("Model not downloaded");
        }
      } catch (e) {
        setStatusMsg("Error: " + String(e));
      }
    })();
  }, []);

  // ── Subscribe to backend events ───────────────────────────────────────────
  useEffect(() => {
    const unlisteners: Promise<() => void>[] = [];

    unlisteners.push(
      listen<{ text: string; speaker: string }>("transcript", (e) => {
        setUtterances((prev) => [
          ...prev,
          { id: utteranceId++, text: e.payload.text, speaker: e.payload.speaker },
        ]);
      })
    );

    unlisteners.push(
      listen("whisper-ready", () => {
        setStatusMsg("Transcribing (mic)");
      })
    );

    unlisteners.push(
      listen<string>("transcript-error", (e) => {
        setStatusMsg("Error: " + e.payload);
        setIsRunning(false);
      })
    );

    unlisteners.push(
      listen<number>("model-download-progress", (e) => {
        setDownloadPct(e.payload);
      })
    );

    unlisteners.push(
      listen("model-download-done", () => {
        setModelState("ready");
        setStatusMsg("Ready");
        setDownloadPct(0);
      })
    );

    return () => {
      unlisteners.forEach((p) => p.then((fn) => fn()));
    };
  }, []);

  // ── Auto-scroll transcript ────────────────────────────────────────────────
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [utterances]);

  // ── Actions ───────────────────────────────────────────────────────────────
  async function downloadModel() {
    setModelState("downloading");
    setStatusMsg("Downloading model (0%)…");
    setDownloadPct(0);
    try {
      await invoke("download_model");
    } catch (e) {
      setStatusMsg("Download failed: " + String(e));
      setModelState("missing");
    }
  }

  async function toggleSession() {
    if (modelState !== "ready") return;
    try {
      if (isRunning) {
        setStatusMsg("Stopping…");
        await invoke("stop_transcription");
        setIsRunning(false);
        setStatusMsg("Ready");
      } else {
        setStatusMsg("Loading model…");
        await invoke("start_transcription");
        setIsRunning(true);
        setStatusMsg("Loading model… (this may take a moment)");
      }
    } catch (e) {
      setStatusMsg("Error: " + String(e));
      setIsRunning(false);
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <div className="container">
      <header className="top-bar">
        <h1>OpenOats</h1>
        <div className="status">{statusMsg}</div>
      </header>

      <main className="transcript-area">
        {utterances.length === 0 ? (
          <p className="placeholder">
            {modelState === "ready"
              ? "Press Start Session and speak…"
              : "Download the model to get started."}
          </p>
        ) : (
          utterances.map((u) => (
            <div key={u.id} className={`utterance ${u.speaker}`}>
              <span className="speaker-label">{u.speaker === "you" ? "You" : "Them"}</span>
              <span className="utterance-text">{u.text}</span>
            </div>
          ))
        )}
        <div ref={bottomRef} />
      </main>

      <footer className="control-bar">
        {modelState === "missing" && (
          <div className="model-notice">
            <p>
              Whisper model not found.
              <br />
              <small>{modelPath}</small>
            </p>
            <button className="download-btn" onClick={downloadModel}>
              Download Model (~150 MB)
            </button>
          </div>
        )}

        {modelState === "downloading" && (
          <div className="model-notice">
            <p>Downloading… {downloadPct}%</p>
            <div className="progress-bar">
              <div className="progress-fill" style={{ width: `${downloadPct}%` }} />
            </div>
          </div>
        )}

        {modelState === "ready" && (
          <button
            className={isRunning ? "stop-btn" : "start-btn"}
            onClick={toggleSession}
          >
            {isRunning ? "Stop Session" : "Start Session"}
          </button>
        )}
      </footer>
    </div>
  );
}

export default App;
