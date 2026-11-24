/**
 * Disclosures: a heading marked data-disclosure opens and closes the part
 * it names in aria-controls (the side column's panels). The part is shown
 * while it has the class show; the heading says so in aria-expanded (its
 * arrow follows that). Pressing the heading, or Enter or Space on it, turns
 * it over; it is in the keyboard's order (tabindex in the view).
 */
(function () {
  'use strict';

  function toggleFor(target) {
    return target && target.closest ? target.closest('[data-disclosure][aria-controls]') : null;
  }

  function turn(toggle) {
    var part = document.getElementById(toggle.getAttribute('aria-controls'));
    if (!part) return;
    var open = !part.classList.contains('show');
    part.classList.toggle('show', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
  }

  document.addEventListener('click', function (event) {
    var toggle = toggleFor(event.target);
    if (!toggle) return;
    event.preventDefault();
    turn(toggle);
  });

  document.addEventListener('keydown', function (event) {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    var toggle = toggleFor(event.target);
    if (!toggle || event.target !== toggle) return;
    event.preventDefault();
    turn(toggle);
  });

  window.MonadicDisclosure = { turn: turn };
})();
