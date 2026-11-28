/**
 * The work screen's four places, one under another (workbench.js fills
 * them): Now (current), Latest, Before (previous) and Put away (stash).
 * Each is a panel as the side column's others are (rounded, shaded), with
 * a head (its icon and name, who placed it, how many items, and the arrow
 * that folds it by hand) and a body that scrolls on its own. An empty Now or Put away folds to its head (Now
 * takes what is placed, Put away what is dragged there); an empty Latest
 * or Before is not shown at all. Between two
 * open places a separator changes their heights (dragged, or with the
 * arrow keys), kept per layout mode.
 *
 * WorkbenchPlaces.build(container, t) → places:
 * - places.regions[name]: { root, head, body, title, count }
 * - places.fill(counts, info): counts { current: n, ... }; info
 *   { layers: { latest: 'user'|'agent', previous: … }, limit, mode }
 * - places.regionOf(node): the place a node is in, or null
 */
(function (window) {
  'use strict';

  const PLACES = ['current', 'latest', 'previous', 'stash'];
  const DESK = ['current', 'latest', 'previous'];
  // The places a turn's layer is in: not shown while empty.
  const LAYERS = ['latest', 'previous'];
  const STORE_KEY = 'monadic.workbench.places.';
  const FOLDED_KEY = 'monadic.workbench.places.folded';
  const ICONS = { current: 'fa-pencil', latest: 'fa-reply', previous: 'fa-clock-rotate-left', stash: 'fa-box-archive' };
  // The least share of the open height a place keeps while resized.
  const MIN_WEIGHT = 0.1;
  const KEY_STEP = 0.05;
  const DEFAULTS = { current: 0.4, latest: 0.3, previous: 0.15, stash: 0.15 };

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function stored(mode) {
    try {
      const raw = window.localStorage && window.localStorage.getItem(STORE_KEY + mode);
      const kept = raw ? JSON.parse(raw) : null;
      if (!kept || typeof kept !== 'object') return Object.assign({}, DEFAULTS);
      const weights = {};
      PLACES.forEach((name) => {
        const value = Number(kept[name]);
        weights[name] = value > 0 && value <= 1 ? value : DEFAULTS[name];
      });
      return weights;
    } catch (_) {
      return Object.assign({}, DEFAULTS);
    }
  }

  function storedFolded() {
    try {
      const raw = window.localStorage && window.localStorage.getItem(FOLDED_KEY);
      const kept = raw ? JSON.parse(raw) : [];
      return Array.isArray(kept) ? kept.filter((name) => PLACES.includes(name)) : [];
    } catch (_) {
      return [];
    }
  }

  function keep(mode, weights) {
    try {
      if (window.localStorage) window.localStorage.setItem(STORE_KEY + mode, JSON.stringify(weights));
    } catch (_) {
      // Not kept: the next page starts from the defaults.
    }
  }

  function build(container, t) {
    const say = typeof t === 'function' ? t : (_key, fallback) => fallback;
    const names = {
      current: say('ui.workbench.placeNow', 'Now'),
      latest: say('ui.workbench.placeLatest', 'Latest'),
      previous: say('ui.workbench.placeBefore', 'Before'),
      stash: say('ui.workbench.placeStash', 'Put away')
    };
    const regions = {};
    const separators = [];
    container.replaceChildren();
    PLACES.forEach((name, index) => {
      if (index > 0) {
        const separator = element('div', 'workbench-place-separator');
        separator.setAttribute('role', 'separator');
        separator.setAttribute('aria-orientation', 'horizontal');
        separator.dataset.after = PLACES[index - 1];
        separator.dataset.before = name;
        separators.push(separator);
        container.appendChild(separator);
      }
      const root = element('section', 'workbench-place rounded shaded-panel');
      root.dataset.place = name;
      const body = element('div', 'workbench-place-body');
      body.dataset.place = name;
      body.id = `workbench-place-${name}`;
      body.setAttribute('aria-label', names[name]);
      // The head as the side column's panels have it: pressing it (or
      // Enter or Space on it) folds or opens the place.
      const head = element('h5', 'workbench-place-head sidebar-collapse-toggle mb-0');
      head.setAttribute('role', 'button');
      head.tabIndex = 0;
      head.setAttribute('aria-controls', body.id);
      const title = element('span', 'text workbench-place-title');
      title.append(element('i', `fa-solid ${ICONS[name]}`), document.createTextNode(` ${names[name]}`));
      const side = element('span', 'workbench-place-side');
      const count = element('span', 'workbench-place-count');
      side.append(count, element('i', 'fas fa-chevron-down sidebar-collapse-icon'));
      head.append(title, side);
      const turn = () => {
        if (folded.has(name)) folded.delete(name);
        else folded.add(name);
        keepFolded();
        apply();
      };
      head.addEventListener('click', turn);
      head.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter' && e.key !== ' ') return;
        e.preventDefault();
        turn();
      });
      root.append(head, body);
      container.appendChild(root);
      regions[name] = { root, head, body, title, count, name: names[name] };
    });

    let mode = 'side';
    let weights = stored(mode);
    // The places the user folded (kept for the next page).
    const folded = new Set(storedFolded());
    function keepFolded() {
      try {
        if (window.localStorage) window.localStorage.setItem(FOLDED_KEY, JSON.stringify(Array.from(folded)));
      } catch (_) {
        // Not kept: the next page opens every place.
      }
    }

    // The open places take the height by their weights; an empty one is
    // only its head.
    function isOpen(name) {
      return !regions[name].root.classList.contains('is-empty') && !folded.has(name);
    }

    function apply() {
      PLACES.forEach((name) => {
        const root = regions[name].root;
        const shut = folded.has(name);
        root.classList.toggle('is-folded', shut);
        // The arrow says whether the user folded it, also for an empty place.
        root.querySelector('.workbench-place-head').setAttribute('aria-expanded', shut ? 'false' : 'true');
      });
      const open = PLACES.filter(isOpen);
      const total = open.reduce((sum, name) => sum + weights[name], 0) || 1;
      PLACES.forEach((name) => {
        const root = regions[name].root;
        root.style.flexGrow = open.includes(name) ? String(weights[name] / total) : '0';
      });
      separators.forEach((separator) => {
        const pair = pairOf(separator, open);
        separator.hidden = !pair;
        if (pair) {
          separator.tabIndex = 0;
          separator.setAttribute('aria-label', `${regions[pair[0]].name} / ${regions[pair[1]].name}`);
          separator.setAttribute('aria-valuenow', String(Math.round((weights[pair[0]] / (weights[pair[0]] + weights[pair[1]])) * 100)));
          separator.setAttribute('aria-valuemin', '0');
          separator.setAttribute('aria-valuemax', '100');
        } else {
          separator.removeAttribute('tabindex');
        }
      });
    }

    // The two open places a separator stands between: the nearest open one
    // above it and below it, and only where it is the one next to the
    // upper of them (one separator for each pair).
    function pairOf(separator, open) {
      const below = PLACES.indexOf(separator.dataset.before);
      const upper = PLACES.slice(0, below).reverse().find((name) => open.includes(name));
      const lower = PLACES.slice(below).find((name) => open.includes(name));
      if (!upper || !lower) return null;
      const nextAfterUpper = PLACES[PLACES.indexOf(upper) + 1];
      return separator.dataset.before === nextAfterUpper ? [upper, lower] : null;
    }

    function move(separator, by) {
      const open = PLACES.filter(isOpen);
      const pair = pairOf(separator, open);
      if (!pair) return;
      const [upper, lower] = pair;
      const sum = weights[upper] + weights[lower];
      const least = MIN_WEIGHT * sum;
      const next = Math.min(Math.max(weights[upper] + by * sum, least), sum - least);
      weights[upper] = next;
      weights[lower] = sum - next;
      keep(mode, weights);
      apply();
    }

    separators.forEach((separator) => {
      separator.addEventListener('keydown', (e) => {
        if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
        e.preventDefault();
        move(separator, e.key === 'ArrowUp' ? -KEY_STEP : KEY_STEP);
      });
      separator.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        const open = PLACES.filter(isOpen);
        const pair = pairOf(separator, open);
        if (!pair) return;
        const span = regions[pair[0]].root.getBoundingClientRect().height + regions[pair[1]].root.getBoundingClientRect().height;
        if (!(span > 0)) return;
        let last = e.clientY;
        if (typeof separator.setPointerCapture === 'function') separator.setPointerCapture(e.pointerId);
        const onMove = (ev) => {
          move(separator, (ev.clientY - last) / span);
          last = ev.clientY;
        };
        const onUp = () => {
          separator.removeEventListener('pointermove', onMove);
          separator.removeEventListener('pointerup', onUp);
          separator.removeEventListener('pointercancel', onUp);
        };
        separator.addEventListener('pointermove', onMove);
        separator.addEventListener('pointerup', onUp);
        separator.addEventListener('pointercancel', onUp);
        e.preventDefault();
      });
    });

    function fill(counts, info) {
      const given = info || {};
      if (given.mode && given.mode !== mode) {
        mode = given.mode;
        weights = stored(mode);
      }
      const layers = given.layers || {};
      PLACES.forEach((name) => {
        const region = regions[name];
        const n = Number(counts && counts[name]) || 0;
        region.root.classList.toggle('is-empty', n === 0);
        region.root.hidden = n === 0 && LAYERS.includes(name);
        // An empty place, open, says it holds nothing.
        const note = region.body.querySelector(':scope > .workbench-place-none');
        if (n === 0 && !note) region.body.appendChild(element('div', 'workbench-place-none text-secondary', say('ui.workbench.placeNone', 'Nothing here')));
        if (n > 0 && note) note.remove();
        let text = name === 'current' && given.limit ? `${n} / ${given.limit}` : String(n);
        const by = layers[name];
        if (by) text = `${by === 'agent' ? say('ui.workbench.placeByAgent', 'AI') : say('ui.workbench.placeByUser', 'You')} · ${text}`;
        region.count.textContent = text;
      });
      apply();
    }

    function regionOf(node) {
      const body = node && node.closest ? node.closest('.workbench-place-body') : null;
      return body ? body.dataset.place : null;
    }

    apply();
    return { regions, separators, fill, regionOf };
  }

  window.WorkbenchPlaces = { PLACES, DESK, build };
})(typeof window !== 'undefined' ? window : globalThis);
