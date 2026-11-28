/**
 * The work screen's present desk (workbench.js fills it): what is on the
 * desk now, Now and Latest in one list (each item tagged with who placed
 * it and when), and under it a drawer of what was put away. Earlier turns'
 * desks are shown from their cards in the conversation, not here. Each is a
 * panel as the side column's others are (rounded, shaded), with a head and
 * a body that scrolls on its own; the drawer folds by hand (kept for the
 * next page, folded at first) and has a box that narrows its rows by name.
 *
 * WorkbenchPlaces.build(container, t) → places:
 * - places.regions[name] (desk, stash): { root, head, body, title, count, name }
 * - places.fill(counts, info): counts { current: n, latest: n, stash: n };
 *   info { limit }
 * - places.regionOf(node): the region a node is in, or null
 * WorkbenchPlaces.regionOf(place): the region an item of a place is shown
 * in (desk, stash), or null (Before is not shown).
 */
(function (window) {
  'use strict';

  const PLACES = ['desk', 'stash'];
  const REGIONS = { current: 'desk', latest: 'desk', stash: 'stash' };
  const OPEN_KEY = 'monadic.workbench.drawer.open';
  const ICONS = { desk: 'fa-pencil', stash: 'fa-box-archive' };

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function storedOpen() {
    try {
      return !!window.localStorage && window.localStorage.getItem(OPEN_KEY) === 'true';
    } catch (_) {
      return false;
    }
  }

  function keepOpen(on) {
    try {
      if (window.localStorage) window.localStorage.setItem(OPEN_KEY, on ? 'true' : 'false');
    } catch (_) {
      // Not kept: the next page starts folded.
    }
  }

  function build(container, t) {
    const say = typeof t === 'function' ? t : (_key, fallback) => fallback;
    const names = {
      desk: say('ui.workbench.placeDesk', 'On the desk'),
      stash: say('ui.workbench.placeStash', 'Put away')
    };
    const regions = {};
    container.replaceChildren();
    PLACES.forEach((name) => {
      const root = element('section', `workbench-place workbench-place-${name} rounded shaded-panel`);
      root.dataset.place = name;
      const body = element('div', 'workbench-place-body');
      body.dataset.place = name;
      body.id = `workbench-place-${name}`;
      body.setAttribute('aria-label', names[name]);
      const head = element('h5', 'workbench-place-head mb-0');
      const title = element('span', 'text workbench-place-title');
      title.append(element('i', `fa-solid ${ICONS[name]}`), document.createTextNode(` ${names[name]}`));
      const side = element('span', 'workbench-place-side');
      const count = element('span', 'workbench-place-count');
      side.appendChild(count);
      head.append(title, side);
      root.append(head);
      if (name === 'stash') {
        // The drawer: its head opens and folds it.
        head.classList.add('sidebar-collapse-toggle');
        head.setAttribute('role', 'button');
        head.tabIndex = 0;
        head.setAttribute('aria-controls', body.id);
        side.appendChild(element('i', 'fas fa-chevron-down sidebar-collapse-icon'));
        const turn = () => setOpen(root.classList.contains('is-folded'));
        head.addEventListener('click', turn);
        head.addEventListener('keydown', (e) => {
          if (e.key !== 'Enter' && e.key !== ' ') return;
          e.preventDefault();
          turn();
        });
        const filter = element('input', 'form-control form-control-sm workbench-stash-filter');
        filter.type = 'search';
        filter.placeholder = say('ui.workbench.stashFilter', 'Find by name');
        filter.setAttribute('aria-label', say('ui.workbench.stashFilter', 'Find by name'));
        filter.addEventListener('input', () => narrow(body, filter.value));
        root.append(filter);
        regions[name] = { root, head, body, title, count, name: names[name], filter };
      } else {
        regions[name] = { root, head, body, title, count, name: names[name] };
      }
      root.append(body);
      container.appendChild(root);
    });

    function setOpen(on) {
      const root = regions.stash.root;
      root.classList.toggle('is-folded', !on);
      regions.stash.head.setAttribute('aria-expanded', on ? 'true' : 'false');
      keepOpen(on);
    }

    // The drawer's rows whose name holds what was typed (any case).
    function narrow(body, text) {
      const wanted = String(text || '').trim().toLowerCase();
      Array.from(body.children).forEach((row) => {
        const name = row.querySelector('.workbench-stash-name');
        if (!name) return;
        row.hidden = wanted !== '' && !name.textContent.toLowerCase().includes(wanted);
      });
    }

    function fill(counts, info) {
      const given = info || {};
      const now = Number(counts && counts.current) || 0;
      const latest = Number(counts && counts.latest) || 0;
      const away = Number(counts && counts.stash) || 0;
      const desk = regions.desk;
      desk.count.textContent = given.limit
        ? `${say('ui.workbench.placeNow', 'Now')} ${now} / ${given.limit}`
        : `${say('ui.workbench.placeNow', 'Now')} ${now}`;
      desk.root.classList.toggle('is-empty', now + latest === 0);
      const note = desk.body.querySelector(':scope > .workbench-place-none');
      if (now + latest === 0 && !note) {
        desk.body.appendChild(element('div', 'workbench-place-none text-secondary', say('ui.workbench.placeNone', 'Nothing here')));
      }
      if (now + latest > 0 && note) note.remove();
      regions.stash.count.textContent = String(away);
      regions.stash.root.classList.toggle('is-empty', away === 0);
      narrow(regions.stash.body, regions.stash.filter.value);
    }

    function regionOf(node) {
      const body = node && node.closest ? node.closest('.workbench-place-body') : null;
      return body ? body.dataset.place : null;
    }

    setOpen(storedOpen());
    return { regions, fill, regionOf };
  }

  window.WorkbenchPlaces = { PLACES, build, regionOf: (place) => REGIONS[place] || null };
})(typeof window !== 'undefined' ? window : globalThis);
