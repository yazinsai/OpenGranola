import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

interface Props {
  isRunning: boolean;
  onStart: () => void;
  onStop: () => void;
  disabled?: boolean;
}

export function ControlBar({ isRunning, onStart, onStop, disabled }: Props) {
  const [devices, setDevices] = useState<string[]>([]);
  const [selectedDevice, setSelectedDevice] = useState<string>("");

  useEffect(() => {
    invoke<string[]>("list_mic_devices").then((d) => {
      setDevices(d);
      if (d.length > 0) setSelectedDevice(d[0]);
    });
  }, []);

  const handleDeviceChange = async (device: string) => {
    setSelectedDevice(device);
    try {
      const settings = await invoke<any>("get_settings");
      await invoke("save_settings", {
        newSettings: { ...settings, inputDeviceName: device || null },
      });
    } catch (e) {
      console.error("Failed to save device:", e);
    }
  };

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "8px 16px", borderBottom: "1px solid #333" }}>
      <select
        value={selectedDevice}
        onChange={(e) => handleDeviceChange(e.target.value)}
        disabled={isRunning}
        style={{ flex: 1, padding: "4px 8px", background: "#1a1a1a", color: "#fff", border: "1px solid #444", borderRadius: 4 }}
      >
        {devices.length === 0 && <option value="">No microphone found</option>}
        {devices.map((d) => <option key={d} value={d}>{d}</option>)}
      </select>

      <button
        onClick={isRunning ? onStop : onStart}
        disabled={disabled}
        style={{
          padding: "6px 20px",
          background: isRunning ? "#c0392b" : "#27ae60",
          color: "#fff",
          border: "none",
          borderRadius: 4,
          cursor: disabled ? "not-allowed" : "pointer",
          fontWeight: 600,
          opacity: disabled ? 0.5 : 1,
        }}
      >
        {isRunning ? "⏹ Stop" : "⏺ Record"}
      </button>
    </div>
  );
}
