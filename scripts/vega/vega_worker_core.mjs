// A Vega-Lite chart of the work screen, checked and drawn to SVG text
// inside a worker (vega_worker_entry.mjs). The spec is a file the model or
// the user wrote, so it is taken only within limits that keep the work
// small and the worker from reading anything: inline values only, a short
// list of transforms, expressions of a small grammar (read with Vega's own
// expression parser, the one that runs them), no URLs, images, links or
// parameters. Expressions run through Vega's interpreter, never as code.
import { parse, View } from 'vega';
import { compile } from 'vega-lite';
import { parseExpression } from 'vega-expression';
import { expressionInterpreter } from 'vega-interpreter';

export const LIMITS = {
  records: 5000,
  fields: 50,
  views: 12,
  depth: 3,
  rows: 100000,
  foldFields: 10,
  pivotLimit: 50,
  side: 2000,
  maxbins: 200,
  literal: 200,
  svgChars: 5 * 1024 * 1024
};

// Keys never taken, wherever they are (outside the data's values). A
// signal is an expression of Vega's own: the charts taken here use none.
const DENIED_KEYS = new Set(['url', 'href', 'usermeta', 'params', 'datasets', 'sequence', 'sphere', 'graticule',
  'selection', 'lookup', 'impute', 'loader', 'signal']);
// The keys each transform takes.
const TRANSFORM_KEYS = {
  filter: ['filter'],
  calculate: ['calculate', 'as'],
  aggregate: ['aggregate', 'groupby'],
  joinaggregate: ['joinaggregate', 'groupby'],
  bin: ['bin', 'field', 'as'],
  timeUnit: ['timeUnit', 'field', 'as'],
  window: ['window', 'frame', 'ignorePeers', 'groupby', 'sort'],
  stack: ['stack', 'groupby', 'as', 'offset', 'sort'],
  fold: ['fold', 'as'],
  pivot: ['pivot', 'value', 'groupby', 'limit', 'op']
};
const TRANSFORMS = Object.keys(TRANSFORM_KEYS);
const COMPOSITION = ['layer', 'concat', 'hconcat', 'vconcat', 'repeat', 'facet'];
const FUNCTIONS = new Set(['abs', 'round', 'floor', 'ceil', 'sqrt', 'log', 'exp', 'pow', 'min', 'max', 'clamp',
  'isValid', 'isNumber', 'isString', 'isDate', 'toNumber', 'toString', 'toDate', 'toBoolean', 'upper', 'lower',
  'trim', 'substring', 'slice', 'indexOf', 'length', 'format', 'timeFormat', 'utcFormat', 'datetime', 'year',
  'month', 'date', 'day', 'hours', 'minutes', 'quarter']);
// Vega transforms a chart taken here never needs (they make data or read it).
const DENIED_VEGA_TRANSFORMS = new Set(['sequence', 'graticule', 'isocontour', 'kde', 'kde2d', 'density',
  'loess', 'regression', 'contour', 'wordcloud', 'force', 'voronoi', 'geojson', 'geopath', 'geopoint',
  'geoshape', 'tree', 'pack', 'partition', 'stratify', 'nest', 'treemap', 'treelinks', 'dotbin', 'quantile',
  'label', 'lookup', 'flatten', 'impute']);

export class Refused extends Error {}

function refuse(message) {
  throw new Refused(message);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// An expression of the small grammar: datum's fields, literals, operators
// and the listed functions.
export function checkExpression(text) {
  if (typeof text !== 'string') refuse('an expression must be text');
  let ast;
  try {
    ast = parseExpression(text);
  } catch (e) {
    refuse(`an expression could not be read: ${e.message}`);
  }
  const walk = (node) => {
    switch (node && node.type) {
      case 'Literal':
        if (typeof node.value === 'string' && node.value.length > LIMITS.literal) refuse('a text in an expression is too long');
        if (node.regex) refuse('regular expressions are not taken');
        return;
      case 'Identifier':
        if (node.name !== 'datum') refuse(`"${node.name}" is not taken in an expression`);
        return;
      case 'MemberExpression':
        walkMember(node);
        return;
      case 'BinaryExpression':
      case 'LogicalExpression':
        walk(node.left);
        walk(node.right);
        return;
      case 'UnaryExpression':
        walk(node.argument);
        return;
      case 'ConditionalExpression':
        walk(node.test);
        walk(node.consequent);
        walk(node.alternate);
        return;
      case 'CallExpression':
        if (!node.callee || node.callee.type !== 'Identifier' || !FUNCTIONS.has(node.callee.name)) {
          refuse(`the function "${node.callee && node.callee.name}" is not taken`);
        }
        node.arguments.forEach(walk);
        return;
      default:
        refuse(`"${node && node.type}" is not taken in an expression`);
    }
  };
  // A field of datum: datum.x or datum["x"], and fields of that.
  const walkMember = (node) => {
    let at = node;
    while (at.type === 'MemberExpression') {
      if (at.computed) {
        if (!at.property || at.property.type !== 'Literal' || typeof at.property.value !== 'string') {
          refuse('a field must be named by text');
        }
      } else if (!at.property || at.property.type !== 'Identifier') {
        refuse('a field must be named');
      }
      at = at.object;
    }
    if (at.type !== 'Identifier' || at.name !== 'datum') refuse('only fields of datum are taken');
  };
  walk(ast);
}

// The data of a spec: inline values only. Returns how many records.
function checkData(data) {
  if (!isObject(data)) refuse('data must be an object with values');
  const keys = Object.keys(data);
  if (keys.some((k) => k !== 'values' && k !== 'format')) refuse('data must hold only values (and format)');
  if (!Array.isArray(data.values)) refuse('data must hold values');
  if (data.format !== undefined) {
    if (!isObject(data.format) || Object.keys(data.format).some((k) => k !== 'parse' && k !== 'type')) {
      refuse('data.format may only say how to parse the values');
    }
    if (data.format.type !== undefined && data.format.type !== 'json') refuse('values are JSON');
  }
  data.values.forEach((record) => {
    if (isObject(record) && Object.keys(record).length > LIMITS.fields) refuse(`a record has more than ${LIMITS.fields} fields`);
  });
  return data.values.length;
}

// A facet's field: a field of the values as they are (no bin, no time
// unit, no expression).
function facetField(def) {
  if (!isObject(def) || typeof def.field !== 'string' || def.bin || def.timeUnit || /[.[\]\\]/.test(def.field)) {
    refuse('a facet must name a field of the values as it is');
  }
  return def.field;
}

function distinctCount(field, values) {
  return new Set(values.map((record) => (isObject(record) ? JSON.stringify(record[field]) : undefined))).size;
}

// Checks a Vega-Lite spec. Returns what was counted.
export function checkSpec(spec) {
  if (!isObject(spec)) refuse('the chart must be a JSON object');
  const state = { records: 0, folds: 0, foldFields: 1, pivots: 0, transforms: [], faceted: false, values: [] };

  const walk = (node, depth) => {
    if (Array.isArray(node)) {
      node.forEach((n) => walk(n, depth));
      return;
    }
    if (!isObject(node)) return;
    Object.entries(node).forEach(([key, value]) => {
      if (DENIED_KEYS.has(key)) refuse(`"${key}" is not taken`);
      if (key === 'data') {
        state.records += checkData(value);
        state.values.push(...value.values);
        return;
      }
      if (key === 'mark' && (value === 'image' || (isObject(value) && value.type === 'image'))) refuse('image marks are not taken');
      if (key === 'transform') {
        if (!Array.isArray(value)) refuse('transform must be a list');
        value.forEach(checkTransform);
        return;
      }
      if ((key === 'expr' || key === 'test') && typeof value === 'string') {
        checkExpression(value);
        return;
      }
      if (key === 'filter' && typeof value === 'string') {
        checkExpression(value);
        return;
      }
      if (key === 'maxbins' && (typeof value !== 'number' || value < 1 || value > LIMITS.maxbins)) {
        refuse(`maxbins must be a number up to ${LIMITS.maxbins}`);
      }
      if ((key === 'width' || key === 'height') && typeof value === 'number' && (value < 0 || value > LIMITS.side)) {
        refuse(`${key} must be at most ${LIMITS.side}`);
      }
      if (key === 'encoding' && isObject(value) && ['row', 'column', 'facet'].some((c) => value[c] !== undefined)) {
        state.faceted = true;
      }
      if (key === 'facet' && isObject(value)) state.faceted = true;
      const nested = COMPOSITION.includes(key) ? depth + 1 : depth;
      if (nested > LIMITS.depth) refuse(`views may be nested ${LIMITS.depth} deep at most`);
      walk(value, nested);
    });
  };

  const checkTransform = (step) => {
    if (!isObject(step)) refuse('a transform must be an object');
    const op = TRANSFORMS.find((name) => name in step);
    if (!op) refuse(`only these transforms are taken: ${TRANSFORMS.join(', ')}`);
    Object.keys(step).forEach((k) => { if (!TRANSFORM_KEYS[op].includes(k)) refuse(`"${k}" is not taken in ${op}`); });
    state.transforms.push(op);
    if (op === 'filter') {
      if (typeof step.filter === 'string') checkExpression(step.filter);
      else walkPredicate(step.filter);
    }
    if (op === 'calculate') checkExpression(step.calculate);
    if (op === 'fold') {
      state.folds += 1;
      if (state.folds > 1) refuse('fold may be used once');
      if (!Array.isArray(step.fold) || step.fold.length > LIMITS.foldFields) refuse(`fold takes at most ${LIMITS.foldFields} fields`);
      state.foldFields = Math.max(1, step.fold.length);
    }
    if (op === 'pivot') {
      state.pivots += 1;
      if (state.pivots > 1) refuse('pivot may be used once');
      if (!Number.isInteger(step.limit) || step.limit < 1 || step.limit > LIMITS.pivotLimit) {
        refuse(`pivot needs a limit of at most ${LIMITS.pivotLimit}`);
      }
    }
    // What the transform holds is checked as everything else is (signals,
    // expressions, keys), a filter's compared values included.
    walk(step, 0);
  };

  // A filter's predicate object: field predicates, and/or/not of them.
  const walkPredicate = (pred) => {
    if (typeof pred === 'string') {
      checkExpression(pred);
      return;
    }
    if (!isObject(pred)) refuse('a filter must be an expression or a predicate');
    if (pred.param || pred.selection) refuse('parameters are not taken');
    ['and', 'or'].forEach((k) => { if (Array.isArray(pred[k])) pred[k].forEach(walkPredicate); });
    if (pred.not !== undefined) walkPredicate(pred.not);
  };

  walk(spec, 0);
  if (state.records > LIMITS.records) refuse(`the chart may hold ${LIMITS.records} records at most`);

  const views = countViews(spec, state);
  if (views > LIMITS.views) refuse(`the chart makes ${views} views; at most ${LIMITS.views}`);
  if (state.faceted && state.transforms.some((op) => op !== 'filter')) {
    refuse('a faceted chart takes only filter transforms');
  }
  const rows = state.records * state.foldFields * views;
  if (rows > LIMITS.rows) refuse('the chart would make too many rows');
  return { records: state.records, views: views, rows: rows };
}

// The views a spec makes: layers and concatenations add up, a repeat
// multiplies by its list, a facet by the distinct values of its fields.
function countViews(node, state) {
  if (!isObject(node)) return 1;
  if (Array.isArray(node.layer)) return node.layer.reduce((sum, child) => sum + countViews(child, state), 0);
  for (const key of ['concat', 'hconcat', 'vconcat']) {
    if (Array.isArray(node[key])) return node[key].reduce((sum, child) => sum + countViews(child, state), 0);
  }
  if (node.repeat !== undefined) {
    const repeat = node.repeat;
    let times = 1;
    if (Array.isArray(repeat)) times = repeat.length;
    else if (isObject(repeat)) {
      ['row', 'column', 'layer'].forEach((k) => {
        if (repeat[k] !== undefined) {
          if (!Array.isArray(repeat[k])) refuse('repeat must list what it repeats');
          times *= repeat[k].length;
        }
      });
    } else refuse('repeat must list what it repeats');
    return times * countViews(node.spec, state);
  }
  let times = 1;
  const facets = [];
  if (isObject(node.facet)) {
    if (typeof node.facet.field === 'string') facets.push(node.facet);
    else ['row', 'column'].forEach((k) => { if (node.facet[k]) facets.push(node.facet[k]); });
  }
  if (isObject(node.encoding)) ['row', 'column', 'facet'].forEach((k) => { if (node.encoding[k]) facets.push(node.encoding[k]); });
  facets.forEach((def) => { times *= distinctCount(facetField(def), state.values); });
  return times * (node.spec ? countViews(node.spec, state) : 1);
}

// The Vega spec Vega-Lite made: inline data only, no transform that makes
// or reads data, no image mark, no link.
export function checkCompiled(vg) {
  (vg.data || []).forEach((d) => {
    if (d.url !== undefined) refuse('compiled data reads an address');
    (d.transform || []).forEach((tr) => {
      if (DENIED_VEGA_TRANSFORMS.has(tr.type)) refuse(`compiled transform "${tr.type}" is not taken`);
    });
  });
  const marks = (node) => {
    (node.marks || []).forEach((mark) => {
      if (mark.type === 'image') refuse('image marks are not taken');
      Object.values(mark.encode || {}).forEach((set) => {
        if (isObject(set) && ('href' in set || 'url' in set)) refuse('links are not taken');
      });
      marks(mark);
    });
  };
  marks(vg);
}

// A loader that gives nothing: no data is read, no address resolved.
const DENY = () => Promise.reject(new Error('nothing is loaded'));
export const denyLoader = { load: DENY, sanitize: DENY, http: DENY, file: DENY };

// The chart's SVG text, or Refused / Error.
export async function render(text) {
  if (typeof text !== 'string') refuse('the chart must be text');
  let spec;
  try {
    spec = JSON.parse(text);
  } catch (e) {
    refuse(`the chart is not JSON: ${e.message}`);
  }
  checkSpec(spec);
  const vg = compile(spec).spec;
  checkCompiled(vg);
  const view = new View(parse(vg, null, { ast: true }), {
    expr: expressionInterpreter, loader: denyLoader, renderer: 'none', logLevel: 0
  });
  try {
    await view.runAsync();
    const svg = await view.toSVG();
    if (svg.length > LIMITS.svgChars) refuse('the chart is too large to show');
    return svg;
  } finally {
    view.finalize();
  }
}
