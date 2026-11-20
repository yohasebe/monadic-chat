// The layer lines `docker pull` and `docker compose pull` print (one per layer
// and step, and with some engines one per update while a layer downloads),
// summed into one figure for a single line on the console. Docker prints
// "<id>: Downloading", Podman "<id> Downloading 1.1GB"; both are read.

const LAYER_LINE = /^\s*([0-9a-f]{12}):?\s+(Pulling fs layer|Waiting|Downloading|Verifying Checksum|Download complete|Extracting|Pull complete|Already exists)\b(.*)$/;
const SIZE = /([0-9]+(?:\.[0-9]+)?)\s*([kKMG]?B)\b/;
const UNITS = { B: 1, kB: 1e3, KB: 1e3, MB: 1e6, GB: 1e9 };

function sizeIn(text) {
  const m = SIZE.exec(text || '');
  return m ? Math.round(parseFloat(m[1]) * UNITS[m[2]]) : null;
}

function formatBytes(bytes) {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${Math.max(0, Math.round(bytes / 1e3))} kB`;
}

// Takes the console's lines in order. take(line) answers whether the line was
// a layer line (then the caller shows progress() instead of the line).
function createPullProgress() {
  const downloaded = new Map();
  return {
    take(line) {
      const m = LAYER_LINE.exec(line);
      if (!m) return false;
      const [, id, step, rest] = m;
      if (!downloaded.has(id)) downloaded.set(id, 0);
      // The first size on a Downloading line is what has arrived ("12MB/45MB").
      const size = step === 'Downloading' ? sizeIn(rest) : null;
      if (size !== null && size > downloaded.get(id)) downloaded.set(id, size);
      return true;
    },
    active() {
      return downloaded.size > 0;
    },
    progress() {
      let bytes = 0;
      downloaded.forEach((n) => { bytes += n; });
      return { layers: downloaded.size, bytes, text: formatBytes(bytes) };
    },
    reset() {
      downloaded.clear();
    }
  };
}

module.exports = { createPullProgress, formatBytes };
