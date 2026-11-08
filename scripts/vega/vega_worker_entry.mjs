// The worker the work screen draws Vega-Lite charts in (built into
// docker/services/ruby/public/vendor/vega/vega-worker.mjs by
// `npm run build:vega`). It takes { id, text } and answers { id, svg } or
// { id, error, refused }. The page ends the worker when a chart takes too
// long.
import { render, Refused } from './vega_worker_core.mjs';

self.onmessage = async (event) => {
  const data = event.data;
  if (!data || typeof data.id !== 'number' || typeof data.text !== 'string') return;
  try {
    self.postMessage({ id: data.id, svg: await render(data.text) });
  } catch (e) {
    self.postMessage({ id: data.id, error: String((e && e.message) || e), refused: e instanceof Refused });
  }
};
