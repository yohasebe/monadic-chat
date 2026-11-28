/**
 * The work screen as an earlier turn left it, shown from the turn's card in
 * the conversation (workbench.js asks the server for it, WORKBENCH_TURN_VIEW,
 * and shows this in place of the present desk). Only looked at: a banner
 * saying which turn it is and that the AI sees the present work screen,
 * then the items of that turn's desk in their order, each tagged with who
 * placed it and where it was, with a line when it changed since or is no
 * longer on the work screen. An image still at that version is shown with
 * the marks it had then, lighter. "Into Now" brings an item that is still
 * on the work screen into the present Now.
 *
 * WorkbenchTurn.show(box, data, { turn, bring, canBring, back, t }):
 * - data: the server's answer ({ status, by, items, assets, put_away })
 * - turn: the card's turn number (or null)
 * - bring(id), canBring(id): bringing an item into Now, and whether it can be
 * - back(): going back to the present desk
 */
(function (window) {
  'use strict';

  function element(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  }

  function iconOf(item) {
    if (item.kind === 'page') return 'fa-globe';
    if (item.kind === 'image' || item.preview === 'image') return 'fa-image';
    if (item.kind === 'browser') return 'fa-globe';
    if (item.kind === 'library') return 'fa-book';
    if (item.preview === 'pdf') return 'fa-file-pdf';
    if (item.preview === 'audio') return 'fa-file-audio';
    if (item.preview === 'video') return 'fa-file-video';
    return 'fa-file-lines';
  }

  function show(box, data, options) {
    const opts = options || {};
    const say = typeof opts.t === 'function' ? opts.t : (_key, fallback) => fallback;
    box.replaceChildren();
    const banner = element('div', 'workbench-turn-banner rounded shaded-panel');
    banner.setAttribute('role', 'status');
    const whose = data && data.by === 'agent'
      ? say('ui.workbench.turnByAgent', "the AI's reply")
      : say('ui.workbench.turnByUser', 'your message');
    const title = opts.turn
      ? say('ui.workbench.turnTitle', 'The work screen at T{turn} ({whose})').replace('{turn}', String(opts.turn))
      : say('ui.workbench.turnTitleNoNumber', 'The work screen at this turn ({whose})');
    const head = element('div', 'workbench-turn-title');
    head.append(element('i', 'fa-solid fa-clock-rotate-left'), document.createTextNode(` ${title.replace('{whose}', whose)}`));
    const back = element('button', 'btn btn-sm btn-secondary workbench-turn-back');
    back.type = 'button';
    back.append(element('i', 'fa-solid fa-arrow-right-to-bracket'), document.createTextNode(` ${say('ui.workbench.backToNow', 'Back to now')}`));
    back.addEventListener('click', () => { if (typeof opts.back === 'function') opts.back(); });
    const top = element('div', 'workbench-turn-top');
    top.append(head, back);
    banner.append(top, element('div', 'workbench-turn-note text-secondary',
      say('ui.workbench.turnAiSees', 'The AI sees the present work screen. To talk about an item here, bring it into Now.')));
    box.appendChild(banner);

    if (!data || data.status !== 'ok') {
      box.appendChild(element('div', 'workbench-turn-none text-secondary',
        say('ui.workbench.turnNone', 'The work screen of this turn was not recorded.')));
      return;
    }
    const list = element('div', 'workbench-turn-items');
    const items = Array.isArray(data.items) ? data.items : [];
    if (items.length === 0) {
      list.appendChild(element('div', 'workbench-turn-none text-secondary', say('ui.workbench.turnEmpty', 'Nothing was on the desk.')));
    }
    items.forEach((item) => list.appendChild(itemOf(item, data, opts, say)));
    box.appendChild(list);
    if (Number(data.put_away) > 0) {
      box.appendChild(element('div', 'workbench-turn-away text-secondary',
        say('ui.workbench.turnPutAway', '{n} put away then').replace('{n}', String(data.put_away))));
    }
  }

  function itemOf(item, data, opts, say) {
    const part = element('section', 'workbench-turn-item rounded shaded-panel');
    part.dataset.item = item.id;
    const bar = element('div', 'workbench-turn-bar');
    const name = element('span', 'workbench-turn-name');
    const label = item.kind === 'browser' ? say('ui.workbench.turnBrowser', 'The browser (open then)') : (item.name || item.kind || '');
    name.append(element('i', `fa-solid ${iconOf(item)}`), document.createTextNode(` ${label}`));
    bar.appendChild(name);
    const who = item.by === 'agent' ? say('ui.workbench.placeByAgent', 'AI') : say('ui.workbench.placeByUser', 'You');
    const places = {
      current: say('ui.workbench.placeNow', 'Now'),
      latest: say('ui.workbench.placeLatest', 'Latest'),
      previous: say('ui.workbench.placeBefore', 'Before')
    };
    bar.appendChild(element('span', `workbench-item-tag is-by-${item.by === 'agent' ? 'agent' : 'user'}`,
      `${who} · ${places[item.place] || places.current}`));
    const bring = element('button', 'btn btn-sm btn-secondary btn-outline workbench-turn-bring');
    bring.type = 'button';
    bring.append(element('i', 'fa-solid fa-arrow-up-from-bracket'), document.createTextNode(` ${say('ui.workbench.bring', 'Into Now')}`));
    const can = item.now !== 'gone' && typeof opts.canBring === 'function' && opts.canBring(item.id);
    bring.disabled = !can;
    bring.addEventListener('click', () => { if (can && typeof opts.bring === 'function') opts.bring(item.id); });
    bar.appendChild(bring);
    part.appendChild(bar);

    // A page of the browser: the address it was at (the browser then is not
    // shown: only the present work screen shows it).
    const address = item.url || (item.page && item.page.url);
    if (address && (item.kind === 'browser' || item.kind === 'page' || item.page)) {
      const line = element('div', 'workbench-turn-state text-secondary');
      line.append(element('i', 'fa-solid fa-globe me-1'), element('code', null, address));
      if (item.kind === 'browser' && item.name) line.append(document.createTextNode(` ${item.name}`));
      part.appendChild(line);
    }
    if (item.now === 'changed') {
      part.appendChild(element('div', 'workbench-turn-state text-secondary',
        say('ui.workbench.turnChanged', 'Changed since this turn: shown as it is now in the present work screen.')));
    } else if (item.now === 'gone') {
      part.appendChild(element('div', 'workbench-turn-state text-secondary',
        say('ui.workbench.turnGone', 'No longer on the work screen.')));
    }
    const url = item.now === 'same' && data.assets ? data.assets[item.id] : null;
    if (url && (item.kind === 'image' || item.preview === 'image')) {
      const frame = element('div', 'workbench-image-frame workbench-turn-image');
      const img = element('img', 'workbench-image');
      img.src = url;
      img.alt = item.name || '';
      img.draggable = false;
      frame.appendChild(img);
      // The marks shown on it then, lighter and fixed.
      const marks = Array.isArray(item.marks) ? item.marks.filter((m) => m && m.rect) : [];
      if (marks.length > 0) {
        const layer = element('div', 'workbench-marks-earlier');
        layer.setAttribute('aria-hidden', 'true');
        marks.forEach((m) => {
          const mark = element('div', `workbench-mark-earlier ${m.shape === 'ellipse' ? 'is-ellipse' : 'is-rect'}`);
          mark.style.left = `${m.rect.x * 100}%`;
          mark.style.top = `${m.rect.y * 100}%`;
          mark.style.width = `${m.rect.w * 100}%`;
          mark.style.height = `${m.rect.h * 100}%`;
          layer.appendChild(mark);
        });
        frame.appendChild(layer);
      }
      // What was drawn on it then, painted over it as the turn sent it.
      const shapes = item.drawing && Array.isArray(item.drawing.shapes) ? item.drawing.shapes : [];
      if (shapes.length > 0) paintOver(frame, img, shapes);
      part.appendChild(frame);
    } else if (Array.isArray(item.marks) && item.marks.length > 0) {
      part.appendChild(element('div', 'workbench-turn-state text-secondary',
        say('ui.workbench.turnMarks', '{n} marks then').replace('{n}', String(item.marks.length))));
    }
    return part;
  }

  // shapes painted on a canvas over img, once it is had, by the board's
  // painter (WorkbenchWhiteboard) on the sheet of the image's proportions.
  function paintOver(frame, img, shapes) {
    const board = window.WorkbenchWhiteboard;
    if (!board || typeof board.paintShapes !== 'function') return;
    const canvas = element('canvas', 'workbench-turn-drawing');
    canvas.setAttribute('aria-hidden', 'true');
    frame.appendChild(canvas);
    const paint = () => {
      const size = board.overlayFrame(img.naturalWidth, img.naturalHeight);
      if (!size) return;
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      const context = canvas.getContext('2d');
      if (context) board.paintShapes(Object.assign({ shapes: shapes }, size), context, canvas.width, canvas.height);
    };
    if (img.complete && img.naturalWidth > 0) paint();
    else img.addEventListener('load', paint, { once: true });
  }

  window.WorkbenchTurn = { show };
})(typeof window !== 'undefined' ? window : globalThis);
