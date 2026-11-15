"""Generate the schematic figures of the web UI (docs/assets/images/figures/ and
docs/ja/assets/images/figures/, one set for each language of the documentation).

A figure's layout is written here. What it shows is read from the page:
- a control's label key, icon and kind from the page's markup
  (docker/services/ruby/views/index.erb and public/js/monadic/*.js),
- the label's text from the page's translations (public/js/i18n/translations.js),
- the colors from the page's tokens (public/css/tokens.css),
- an icon's outline from the icon font the page loads (public/vendor/webfonts),
  read only when the file is the one bin/assets_list.sh pins by its sha256.
A control that is renamed changes its figure; one that is removed stops this
script.

Run from the repository root:

    python3 scripts/generate_ui_figures.py

Needs python3 with fontTools, and node (for the translations and to read the
compressed font). Edit this file, not the generated SVGs.
"""
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import types
from html import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUBY = os.path.join(ROOT, 'docker', 'services', 'ruby')
# A page's images are beside it: docs/assets for English, docs/ja/assets for Japanese.
OUT = {'en': os.path.join(ROOT, 'docs', 'assets', 'images', 'figures'),
       'ja': os.path.join(ROOT, 'docs', 'ja', 'assets', 'images', 'figures')}
LANGUAGES = ['en', 'ja']


# fontTools reads .woff2 through a module named brotli; node has the decoder.
def _brotli_decompress(data):
    code = ("const c=[];process.stdin.on('data',d=>c.push(d)).on('end',()=>"
            "process.stdout.write(require('zlib').brotliDecompressSync(Buffer.concat(c))))")
    return subprocess.run(['node', '-e', code], input=data, capture_output=True, check=True).stdout


sys.modules['brotli'] = types.SimpleNamespace(decompress=_brotli_decompress)
from fontTools.pens.svgPathPen import SVGPathPen  # noqa: E402
from fontTools.ttLib import TTFont  # noqa: E402


def read(*parts):
    with open(os.path.join(RUBY, *parts), encoding='utf-8') as f:
        return f.read()


def vendor(folder, name):
    """A third-party file of public/vendor, only as bin/assets_list.sh pins it.

    These files are downloaded, not tracked; the list (tracked) names each
    one's sha256. A file that differs from its entry stops this script.
    """
    entry = re.search(r'"[a-z]+,[^,"]+,%s,([0-9a-f]{64})"' % re.escape(name), read('bin', 'assets_list.sh'))
    if not entry:
        raise SystemExit('bin/assets_list.sh has no entry for %s' % name)
    path = os.path.join(RUBY, 'public', 'vendor', folder, name)
    with open(path, 'rb') as f:
        data = f.read()
    if hashlib.sha256(data).hexdigest() != entry.group(1):
        raise SystemExit('%s is not the file bin/assets_list.sh pins; download the assets again' % path)
    return data


# ---- the page's own definitions -------------------------------------------
def translations(languages):
    # The table is the file's first statement; what follows it needs a page.
    code = """
      const vm = require('vm'), fs = require('fs');
      const source = fs.readFileSync(process.argv[1], 'utf8');
      const table = source.slice(0, source.indexOf('\\nclass WebUIi18n'));
      const langs = JSON.parse(process.argv[2]);
      process.stdout.write(vm.runInNewContext(table + '\\n;JSON.stringify(Object.fromEntries(' +
        JSON.stringify(langs) + '.map(l => [l, webUITranslations[l]])))'));
    """
    path = os.path.join(RUBY, 'public', 'js', 'i18n', 'translations.js')
    out = subprocess.run(['node', '-e', code, path, json.dumps(languages)], capture_output=True, check=True)
    return json.loads(out.stdout)


def label(table, key):
    value = table
    for part in key.split('.'):
        value = value[part]          # KeyError: the key the page names is gone
    return value


def tokens():
    css = read('public', 'css', 'tokens.css')
    light = css[:css.index('.dark-theme {')]
    found = dict(re.findall(r'--([a-z0-9-]+):\s*([^;]+);', light))

    def resolve(name):
        value = found[name].strip()
        m = re.fullmatch(r'var\(--([a-z0-9-]+)\)', value)
        return resolve(m.group(1)) if m else value
    return resolve


ICON = r'<i class="(fas|far|fa-solid|fa-regular) (fa-[a-z0-9-]+)[^"]*"'
I18N = r'data-i18n="([^"]+)"'


def element(html, tag, element_id):
    return re.search(r'<%s\b[^>]*\bid="%s"[^>]*>.*?</%s>' % (tag, re.escape(element_id), tag), html, re.S).group(0)


def page_buttons(ids):
    """id -> {kind, style, icon, key} of the page's buttons."""
    html = read('views', 'index.erb')
    out = {}
    for button_id in ids:
        tag = element(html, 'button', button_id)
        kind = re.search(r'\bbtn-(primary|secondary|warning|info|danger|success)\b', tag).group(1)
        style, icon = re.search(ICON, tag).groups()
        out[button_id] = {'kind': kind, 'style': style, 'icon': icon, 'key': re.search(I18N, tag).group(1)}
    return out


def card_functions():
    """The assistant card's functions, in the card's order: [(name, style, icon)]."""
    source = read('public', 'js', 'monadic', 'card-renderer.js')
    block = source[source.index('func-play') - 400:source.index('func-play') + 500]
    found = re.findall(r'class="func-([a-z]+) [^"]*"><i class="(fas|far|fa-solid|fa-regular) (fa-[a-z0-9-]+)"', block)
    names = [name for name, _, _ in found]
    start = names.index('copy', names.index('play') - 1 if 'play' in names else 0)
    return found[start:start + 5]


def side_tabs():
    """The side column's tabs: [key]."""
    html = read('views', 'index.erb')
    return [re.search(I18N, element(html, 'button', 'side-tab-%s' % pane)).group(1)
            for pane in ('settings', 'work', 'files', 'history')]


def live_conversation_keys():
    """The label keys the Live Conversation controls ask the translations for."""
    source = read('public', 'js', 'monadic', 'live-conversation.js')
    wanted = ['lcVoice', 'lcSpeed', 'lcCardView', 'lcTools', 'lcTurnDetection', 'lcTurnSilence', 'lcStart']
    for name in wanted:
        if "t('ui.messages.%s'" % name not in source:
            raise KeyError('live-conversation.js no longer asks for ui.messages.%s' % name)
    return {name: 'ui.messages.%s' % name for name in wanted}


class Icons:
    """Outlines of the icons the page shows, from its icon font."""
    FILES = {'fas': 'fa-solid-900.woff2', 'fa-solid': 'fa-solid-900.woff2',
             'far': 'fa-regular-400.woff2', 'fa-regular': 'fa-regular-400.woff2',
             'fab': 'fa-brands-400.woff2'}
    fonts = {}

    def __init__(self):
        css = vendor('css', 'all.min.css').decode('utf-8')
        # One rule may name several icons: .fa-a,.fa-b{--fa:"\f000"}
        self.codes = {}
        for selectors, code in re.findall(r'((?:\.fa-[a-z0-9-]+,?)+)\{--fa:"\\([0-9a-f]+)"', css):
            for name in selectors.strip(',').split(','):
                self.codes[name[1:]] = int(code, 16)
        self.used = {}

    def use(self, style, name):
        key = '%s-%s' % (self.FILES[style].split('-')[1], name[3:])
        if key not in self.used:
            if self.FILES[style] not in Icons.fonts:
                Icons.fonts[self.FILES[style]] = TTFont(io.BytesIO(vendor('webfonts', self.FILES[style])))
            font = Icons.fonts[self.FILES[style]]
            glyph_name = font.getBestCmap()[self.codes[name]]
            glyphs = font.getGlyphSet()
            pen = SVGPathPen(glyphs)
            glyphs[glyph_name].draw(pen)
            self.used[key] = (pen.getCommands(), glyphs[glyph_name].width, font['head'].unitsPerEm)
        return key

    def symbols(self):
        return '\n'.join(
            '    <symbol id="i-%s" viewBox="0 %d %d %d"><path transform="scale(1 -1)" d="%s"/></symbol>'
            % (key, -em * 0.875, width, em, path) for key, (path, width, em) in sorted(self.used.items()))

    def ratio(self, key):
        _, width, em = self.used[key]
        return width / em


# ---- drawing ---------------------------------------------------------------
FONT = "-apple-system, 'Hiragino Sans', 'Noto Sans JP', 'Helvetica Neue', Arial, sans-serif"
BUTTON_HEIGHT = 28
TEXT = 13


def text_width(text, size=TEXT, weight=None):
    """An estimate, on the generous side: the reader's fonts decide the real width."""
    latin = 0.67 if weight in ('600', '700') else 0.61
    return sum(size * (1.0 if ord(ch) > 0x2E7F else latin) for ch in text)


class Figure:
    def __init__(self, color, title):
        self.color, self.title = color, title
        self.icons = Icons()
        self.parts = []
        self.number = 0
        self.width = self.height = 0
        self.extra_defs = ''
        self.ground = None

    def add(self, svg):
        self.parts.append(svg)

    def grow(self, right, bottom):
        self.width, self.height = max(self.width, right), max(self.height, bottom)

    def text(self, x, y, text, size=TEXT, fill=None, weight=None, anchor=None):
        self.add('<text x="%.1f" y="%.1f" font-size="%d" fill="%s"%s%s>%s</text>' % (
            x, y, size, fill or self.color('text-primary'),
            ' font-weight="%s"' % weight if weight else '', ' text-anchor="%s"' % anchor if anchor else '', escape(text)))
        return text_width(text, size, weight)

    def icon(self, style, name, x, y, size=TEXT, fill=None):
        key = self.icons.use(style, name)
        width = size * self.icons.ratio(key)
        self.add('<use href="#i-%s" x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s"/>'
                 % (key, x, y, width, size, fill or self.color('text-primary')))
        return width

    def callout(self, cx, cy):
        """A numbered mark; the document's list says what each number is."""
        self.number += 1
        self.add('<circle cx="%.1f" cy="%.1f" r="9" fill="%s"/>' % (cx, cy, self.color('text-primary')))
        self.text(cx, cy + 4, str(self.number), 11, '#ffffff', '700', 'middle')

    def button(self, x, y, kind, style, icon, text, mark=True):
        fills = {'warning': ('pal-amber-mid', None), 'primary': ('pal-accent-strong', '#ffffff'),
                 'secondary': ('pal-grey-strong', '#ffffff'), 'info': ('pal-accent-mid', None),
                 'live': ('btn-live-bg', '#ffffff')}
        fill, ink = fills[kind]
        ink = ink or self.color('text-primary')
        pad = 9
        key = self.icons.use(style, icon)
        icon_width = TEXT * self.icons.ratio(key)
        width = pad + icon_width + 5 + text_width(text) + pad + 3
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%d" rx="4" fill="%s"/>'
                 % (x, y, width, BUTTON_HEIGHT, self.color(fill)))
        self.icon(style, icon, x + pad, y + (BUTTON_HEIGHT - TEXT) / 2, TEXT, ink)
        self.text(x + pad + icon_width + 5, y + BUTTON_HEIGHT / 2 + TEXT * 0.36, text, TEXT, ink)
        if mark:
            self.callout(x + width / 2, y - 13)
        self.grow(x + width, y + BUTTON_HEIGHT)
        return width

    def field(self, x, y, width, height, text=None):
        self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="5" fill="#ffffff" stroke="%s"/>'
                 % (x, y, width, height, self.color('border-color')))
        if text:
            self.text(x + 9, y + height / 2 + TEXT * 0.36, text)
        self.grow(x + width, y + height)

    def select(self, x, y, text, width=None):
        width = width or text_width(text) + 40
        self.field(x, y, width, BUTTON_HEIGHT, text)
        self.add('<path d="M%.1f %.1f l4 5 l4 -5 z" fill="%s"/>' % (x + width - 18, y + 12, self.color('pal-grey-strong')))
        return width

    def checkbox(self, x, y, text, on=False):
        size = 14
        self.add('<rect x="%.1f" y="%.1f" width="%d" height="%d" rx="3" fill="%s" stroke="%s"/>'
                 % (x, y + (BUTTON_HEIGHT - size) / 2, size, size,
                    self.color('pal-accent-strong') if on else '#ffffff', self.color('border-color')))
        width = size + 6 + self.text(x + size + 6, y + BUTTON_HEIGHT / 2 + TEXT * 0.36, text)
        self.grow(x + width, y + BUTTON_HEIGHT)
        return width

    def lines(self, x, y, widths):
        """Text that is not the figure's subject, as bars."""
        for i, width in enumerate(widths):
            self.add('<rect x="%.1f" y="%.1f" width="%.1f" height="8" rx="4" fill="%s"/>'
                     % (x, y + i * 16, width, self.color('pal-grey-line')))
        self.grow(x + max(widths), y + len(widths) * 16)

    def svg(self, pad=20):
        width, height = self.width + pad, self.height + pad
        if self.ground:
            ground = '<rect width="%.0f" height="%.0f" fill="%s"/>' % (width, height, self.ground)
        else:
            ground = ('<rect x="0.5" y="0.5" width="%.0f" height="%.0f" rx="12" fill="%s" stroke="%s"/>'
                      % (width - 1, height - 1, self.color('pal-grey-soft'), self.color('pal-grey-line')))
        return ('<svg xmlns="http://www.w3.org/2000/svg" role="img" width="%.0f" height="%.0f" viewBox="0 0 %.0f %.0f" '
                'font-family="%s">\n  <title>%s</title>\n  <defs>\n%s\n  </defs>\n  %s\n</svg>\n'
                % (width, height, width, height, FONT, escape(self.title), self.icons.symbols() + ('\n    ' + self.extra_defs if self.extra_defs else ''),
                   '\n  '.join([ground] + self.parts)))


# ---- the figures -------------------------------------------------------------
def input_buttons(table, color, title):
    """The buttons under the message box."""
    figure = Figure(color, title)
    rows = [['image-file', 'doc', 'url', 'anonymize', 'voice'], ['send', 'clear']]
    specs = page_buttons([b for row in rows for b in row])
    y = 20 + 64 + 30
    for row in rows:
        x = 20
        for button_id in row:
            spec = specs[button_id]
            x += figure.button(x, y, spec['kind'], spec['style'], spec['icon'], label(table, spec['key'])) + 8
        y += BUTTON_HEIGHT + 30
    figure.parts.insert(0, '<rect x="20" y="20" width="%.1f" height="64" rx="6" fill="#ffffff" stroke="%s"/>'
                        % (figure.width - 20, color('border-color')))
    return figure


def message_buttons(table, color, title):
    """The buttons in the header of an assistant's card."""
    figure = Figure(color, title)
    width, x, y = 520, 20, 34
    figure.add('<rect x="%d" y="%d" width="%d" height="118" rx="6" fill="#ffffff" stroke="%s"/>'
               % (x, y, width, color('border-color')))
    # The card's body in its role's color, under a white header
    figure.add('<path d="M%d %d H%d V%d A6 6 0 0 1 %d %d H%d A6 6 0 0 1 %d %d Z" fill="%s"/>'
               % (x + 1, y + 40, x + width - 1, y + 112, x + width - 7, y + 117, x + 7, x + 1, y + 112,
                  color('bg-card-assistant')))
    figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s"/>' % (x, y + 40, x + width, y + 40, color('border-color')))
    figure.icon('fas', 'fa-robot', x + 14, y + 12, 16, color('color-assistant'))
    figure.text(x + 40, y + 25, 'Assistant', 14, color('color-assistant'), '700')
    cx = x + width - 14
    figure.add('<circle cx="%.1f" cy="%.1f" r="6" fill="%s"/>' % (cx - 6, y + 20, color('pal-green-mid')))
    marks = [(cx - 6, 'dot')]
    cx -= 26
    figure.add('<rect x="%.1f" y="%.1f" width="30" height="22" rx="4" fill="%s" stroke="%s"/>'
               % (cx - 30, y + 9, color('pal-red-soft'), color('pal-red-line')))
    figure.text(cx - 15, y + 25, 'T1', 13, color('pal-red-text'), '600', 'middle')
    marks.append((cx - 15, 'turn'))
    cx -= 46
    for _, style, icon in reversed(card_functions()):
        key = figure.icons.use(style, icon)
        icon_width = 15 * figure.icons.ratio(key)
        figure.icon(style, icon, cx - icon_width, y + 12, 15, color('pal-grey-strong'))
        marks.append((cx - icon_width / 2, icon))
        cx -= icon_width + 16
    for mark_x, _ in reversed(marks):
        figure.callout(mark_x, y - 13)
    figure.lines(x + 16, y + 58, [width - 60, width - 120, width - 220])
    figure.grow(x + width, y + 118)
    return figure


def knowledge_base(table, color, title):
    """The Knowledge Base panel of the menu."""
    figure = Figure(color, title)
    x, y, width = 20, 20, 400
    figure.add('<rect x="%d" y="%d" width="%d" height="166" rx="6" fill="#ffffff" stroke="%s"/>'
               % (x, y, width, color('pal-grey-line')))
    figure.icon('fas', 'fa-book', x + 14, y + 16, 15, color('pal-amber-mid'))
    figure.text(x + 38, y + 29, re.sub(r'<[^>]+>\s*', '', label(table, 'ui.knowledgeBase')).strip(), 15, None, '600')
    specs = page_buttons(['library-save', 'library-browse'])
    bx = x + 14
    for button_id in ('library-save', 'library-browse'):
        spec = specs[button_id]
        bx += figure.button(bx, y + 70, spec['kind'], spec['style'], spec['icon'], label(table, spec['key'])) + 8
    figure.add('<rect x="%d" y="%d" width="28" height="15" rx="7.5" fill="%s"/><circle cx="%d" cy="%.1f" r="5.5" fill="#ffffff"/>'
               % (x + 14, y + 134, color('pal-accent-mid'), x + 34, y + 141.5))
    figure.callout(x + 28, y + 119)
    figure.text(x + 50, y + 146, label(table, 'ui.libRagToggleLabel'), 12, color('pal-grey-text'))
    figure.grow(x + width, y + 166)
    return figure


def live_conversation(table, color, title):
    """The controls of Live Conversation."""
    figure = Figure(color, title)
    keys = live_conversation_keys()
    word = lambda name: label(table, keys[name])  # noqa: E731
    x, y = 20, 34
    grey = color('pal-grey-text')

    def named(name):
        nonlocal x
        start = x
        x += figure.text(x, y + BUTTON_HEIGHT / 2 + TEXT * 0.36, word(name), TEXT, grey) + 8
        return start

    start = named('lcVoice')
    x += figure.select(x, y, 'alloy', 110)
    figure.callout((start + x) / 2, y - 13)
    x += 20
    start = named('lcSpeed')
    figure.add('<rect x="%.1f" y="%.1f" width="90" height="5" rx="2.5" fill="%s"/><circle cx="%.1f" cy="%.1f" r="7" fill="%s"/>'
               % (x, y + 11.5, color('pal-grey-line'), x + 58, y + 14, color('pal-accent-strong')))
    x += 96
    x += figure.text(x, y + BUTTON_HEIGHT / 2 + TEXT * 0.36, '1.0', TEXT, grey)
    figure.callout((start + x) / 2, y - 13)
    x += 20
    for name in ('lcCardView', 'lcTools'):
        start = x
        x += figure.checkbox(x, y, word(name))
        figure.callout((start + x) / 2, y - 13)
        x += 20
    right = x - 20
    x, y = 20, y + BUTTON_HEIGHT + 34
    start = named('lcTurnDetection')
    x += figure.select(x, y, word('lcTurnSilence'))
    figure.callout((start + x) / 2, y - 13)
    y += BUTTON_HEIGHT + 34
    figure.button(20, y, 'live', 'fas', 'fa-play', word('lcStart'))
    figure.grow(right, y + BUTTON_HEIGHT)
    return figure


def side_column(table, color, title):
    """The tabs of the side column."""
    figure = Figure(color, title)
    x, y = 20, 34
    figure.add('<rect x="%d" y="%d" width="{w}" height="38" rx="6" fill="%s"/>' % (x, y, color('pal-grey-line')))
    tx = x + 6
    for i, key in enumerate(side_tabs()):
        text = label(table, key)
        width = text_width(text, 14) + 26
        if i == 1:
            figure.add('<rect x="%.1f" y="%.1f" width="%.1f" height="28" rx="5" fill="#ffffff"/>' % (tx, y + 5, width))
        figure.text(tx + width / 2, y + 24, text, 14, None if i == 1 else color('pal-grey-text'),
                    '600' if i == 1 else None, 'middle')
        figure.callout(tx + width / 2, y - 13)
        tx += width + 4
    panel_width = max(tx + 6 - x, 420)
    figure.parts[0] = figure.parts[0].replace('{w}', '%d' % panel_width)
    figure.add('<rect x="%d" y="%d" width="%d" height="120" rx="6" fill="#ffffff" stroke="%s"/>'
               % (x, y + 48, panel_width, color('pal-grey-line')))
    figure.lines(x + 16, y + 66, [panel_width - 60, panel_width - 140, panel_width - 90, panel_width - 200])
    figure.grow(x + panel_width, y + 168)
    return figure



def url_dialog(table, color, title):
    """The dialog of the Open URL button."""
    figure = Figure(color, title)
    html = read('views', 'index.erb')
    modal = html[html.index('id="urlModal"'):html.index('id="urlModal"') + 2600]
    keys = re.findall(I18N, modal) + re.findall(r'data-i18n-placeholder="([^"]+)"', modal)
    wanted = ['ui.modals.fromURL', 'ui.modals.labelOptional', 'ui.modals.urlToFetch', 'ui.cancel',
              'ui.modals.takeInAsText', 'ui.modals.openInWorkScreen', 'ui.modals.urlLabelPlaceholder',
              'ui.modals.urlAddressPlaceholder']
    missing = [key for key in wanted if key not in keys]
    if missing:
        raise SystemExit('the Open URL dialog no longer has %s' % ', '.join(missing))
    word = lambda key: label(table, key)  # noqa: E731
    quiet, line = color('pal-grey-text'), color('pal-grey-line')
    x, y, width = 20, 20, 460
    figure.add('<rect x="%d" y="%d" width="%d" height="268" rx="6" fill="#ffffff" stroke="%s"/>' % (x, y, width, line))
    figure.icon('fa-solid', 'fa-globe', x + 18, y + 17, 15)
    figure.text(x + 42, y + 30, word('ui.modals.fromURL'), 15, None, '700')
    figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s"/>' % (x, y + 48, x + width, y + 48, line))
    figure.text(x + 18, y + 76, word('ui.modals.labelOptional'), 13)
    figure.field(x + 18, y + 86, width - 36, 30)
    figure.text(x + 28, y + 106, word('ui.modals.urlLabelPlaceholder'), 12, color('pal-grey-mid'))
    figure.text(x + 18, y + 144, word('ui.modals.urlToFetch'), 13)
    figure.field(x + 18, y + 154, width - 36, 30)
    figure.text(x + 28, y + 174, word('ui.modals.urlAddressPlaceholder'), 12, color('pal-grey-mid'))
    figure.callout(x + width - 30, y + 154 - 13)
    figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s"/>' % (x, y + 204, x + width, y + 204, line))
    # The footer's buttons, from the right as the dialog has them
    right, marks = x + width - 18, []
    for key, fill, ink, mark in [('ui.modals.openInWorkScreen', 'pal-accent-strong', '#ffffff', True),
                                 ('ui.modals.takeInAsText', 'pal-grey-strong', '#ffffff', True),
                                 ('ui.cancel', 'pal-grey-strong', '#ffffff', False)]:
        text = word(key)
        w = text_width(text) + 22
        figure.add('<rect x="%.1f" y="%d" width="%.1f" height="%d" rx="4" fill="%s"/>'
                   % (right - w, y + 226, w, BUTTON_HEIGHT, color(fill)))
        figure.text(right - w / 2, y + 226 + BUTTON_HEIGHT / 2 + TEXT * 0.36, text, TEXT, ink, None, 'middle')
        if mark:
            marks.append(right - w / 2)
        right -= w + 8
    for cx in sorted(marks):                      # numbered from the left, as they are read
        figure.callout(cx, y + 213)
    figure.grow(x + width, y + 268)
    return figure


def role_selector(table, color, title):
    """The Role selector, open."""
    figure = Figure(color, title)
    html = read('views', 'index.erb')
    values = re.findall(r'<option value="([a-z-]+)">', element(html, 'select', 'select-role'))
    names = {'user': 'user', 'sample-user': 'sampleUser', 'sample-assistant': 'sampleAssistant',
             'sample-system': 'sampleSystem'}
    if values != list(names):
        raise SystemExit('the Role selector has %s; the figure draws %s' % (values, list(names)))
    options = [label(table, 'ui.roleOptions.%s' % names[value]) for value in values]
    quiet, line = color('pal-grey-text'), color('pal-grey-line')
    x, y = 20, 20
    width = max(text_width(text) for text in options) + 50
    start = x + figure.text(x, y + BUTTON_HEIGHT / 2 + TEXT * 0.36, label(table, 'ui.role'), TEXT, quiet) + 10
    figure.select(start, y, options[0], width)
    figure.add('<rect x="%.1f" y="%d" width="%.1f" height="%d" rx="5" fill="#ffffff" stroke="%s"/>'
               % (start, y + 34, width, len(options) * 28 + 8, line))
    for i, text in enumerate(options):
        top = y + 38 + i * 28
        if i == 0:
            figure.add('<rect x="%.1f" y="%d" width="%.1f" height="28" rx="3" fill="%s"/>'
                       % (start + 4, top, width - 8, color('pal-grey-soft')))
        figure.text(start + 12, top + 19, text)
        figure.callout(start + width + 18, top + 14)
    figure.grow(start + width + 30, y + 42 + len(options) * 28)
    return figure


def voice_input(table, color, title):
    """The message box while recording, and the confidence value after it."""
    figure = Figure(color, title)
    recording = read('public', 'js', 'monadic', 'recording.js')
    if "webUIi18n.t('ui.stopButton')" not in recording or 'fa-microphone' not in recording:
        raise SystemExit('recording.js no longer names the Stop button as the voice figure reads it')
    handlers = read('public', 'js', 'monadic', 'websocket-handlers.js')
    value = re.search(r"pValueEl\.textContent = '([^']+)' \+ data\.logprob", handlers)
    if not value:
        raise SystemExit('websocket-handlers.js no longer writes the p-value line as the voice figure reads it')
    x, y, width = 20, 34, 520
    figure.field(x, y, width, 64)
    figure.callout(x + width - 20, y - 13)
    figure.lines(x + 14, y + 16, [width - 150, width - 260])
    figure.text(x, y + 88, value.group(1) + '0.95', 12, color('pal-grey-text'))
    figure.callout(x + width - 20, y + 84)
    row = y + 128
    # While recording the button is the danger kind and reads Stop
    stop = label(table, 'ui.stopButton')
    w = 9 + 13 * 0.75 + 5 + text_width(stop) + 12
    figure.add('<rect x="%d" y="%d" width="%.1f" height="%d" rx="4" fill="%s"/>'
               % (x, row, w, BUTTON_HEIGHT, color('pal-red-strong')))
    iw = figure.icon('fas', 'fa-microphone', x + 9, row + (BUTTON_HEIGHT - TEXT) / 2, TEXT, '#ffffff')
    figure.text(x + 9 + iw + 5, row + BUTTON_HEIGHT / 2 + TEXT * 0.36, stop, TEXT, '#ffffff')
    figure.callout(x + w / 2, row - 13)
    # The level of the voice, beside the button
    heights = [6, 12, 20, 9, 16, 24, 14, 7, 18, 22, 11, 5, 15, 21, 10, 8, 17, 13, 6, 19]
    bx = x + w + 14
    for i, h in enumerate(heights):
        figure.add('<rect x="%.1f" y="%.1f" width="4" height="%d" rx="2" fill="%s"/>'
                   % (bx + i * 7, row + (BUTTON_HEIGHT - h) / 2, h, color('pal-accent-mid')))
    figure.callout(bx + len(heights) * 7 / 2, row - 13)
    figure.grow(x + width, row + BUTTON_HEIGHT)
    return figure


def attachments(table, color, title):
    """Files attached to the message, above the message box."""
    figure = Figure(color, title)
    source = read('public', 'js', 'monadic', 'select_image.js')
    for needed in ('attachment-chip-name', 'remove-file', 'fa-file-pdf', 'fa-image', 'fa-times'):
        if needed not in source:
            raise SystemExit('select_image.js no longer makes an attachment chip with %s' % needed)
    x, y, width = 20, 34, 520
    cx = x
    for icon, name in (('fa-image', 'photo.png'), ('fa-file-pdf', 'report.pdf')):
        w = 12 + 13 + 6 + text_width(name) + 12
        figure.add('<rect x="%.1f" y="%d" width="%.1f" height="%d" rx="4" fill="#ffffff" stroke="%s"/>'
                   % (cx, y, w + 30, BUTTON_HEIGHT, color('border-color')))
        iw = figure.icon('fas', icon, cx + 12, y + (BUTTON_HEIGHT - TEXT) / 2, TEXT, color('pal-grey-strong'))
        figure.text(cx + 12 + iw + 6, y + BUTTON_HEIGHT / 2 + TEXT * 0.36, name)
        figure.add('<rect x="%.1f" y="%d" width="22" height="20" rx="3" fill="%s"/>'
                   % (cx + w + 4, y + 4, color('pal-grey-strong')))
        figure.icon('fas', 'fa-times', cx + w + 10.5, y + 8.5, 11, '#ffffff')
        if cx == x:                               # the two parts of a chip, marked once
            figure.callout(cx + (w - 4) / 2, y - 13)
            figure.callout(cx + w + 15, y - 13)
        cx += w + 30 + 10
    figure.field(x, y + 40, width, 64)
    figure.lines(x + 14, y + 56, [width - 180])
    figure.grow(x + width, y + 104)
    return figure


def page_keys(wanted):
    """The label keys a figure shows, each one named by the page's markup."""
    html = read('views', 'index.erb')
    missing = [key for key in wanted if 'data-i18n="%s"' % key not in html]
    if missing:
        raise SystemExit('views/index.erb no longer names %s' % ', '.join(missing))


def plain(text):
    """A label without the markup some translations carry."""
    return re.sub(r'<[^>]+>\s*', '', text).strip()


def system_settings(table, color, title):
    """The settings a session starts with."""
    figure = Figure(color, title)
    page_keys(['ui.baseApp', 'ui.maxContextSize', 'ui.maxOutputTokens', 'ui.model', 'ui.showAllModels',
               'ui.reasoningEffort', 'ui.showThinking', 'ui.temperature', 'ui.initialPromptAssistant'])
    word = lambda key: plain(label(table, key))  # noqa: E731
    quiet, line = color('pal-grey-text'), color('pal-grey-line')
    x, y, width = 20, 20, 700
    figure.add('<rect x="%d" y="%d" width="%d" height="372" rx="6" fill="#ffffff" stroke="%s"/>' % (x, y, width, line))

    def name(key, lx, ly):
        """A setting's name, with its mark before it."""
        figure.callout(lx - 22, ly - 4)
        return figure.text(lx, ly, word(key), 13, None, '600')

    def switch(sx, sy, on=True):
        figure.add('<rect x="%d" y="%d" width="28" height="15" rx="7.5" fill="%s"/><circle cx="%d" cy="%.1f" r="5.5" fill="#ffffff"/>'
                   % (sx, sy, color('pal-accent-mid') if on else color('pal-grey-mid'), sx + (20 if on else 8), sy + 7.5))

    def blank_select(sx, sy, w, bar):
        """A selector whose value is not the figure's subject."""
        figure.field(sx, sy, w, BUTTON_HEIGHT)
        figure.add('<rect x="%d" y="%d" width="%d" height="8" rx="4" fill="%s"/>' % (sx + 10, sy + 10, bar, line))
        figure.add('<path d="M%.1f %.1f l4 5 l4 -5 z" fill="%s"/>' % (sx + w - 18, sy + 12, color('pal-grey-strong')))

    first, second = x + 44, x + 330
    # The app, and how much of the conversation and of a reply is kept
    name('ui.baseApp', first, y + 34)
    figure.select(first, y + 44, 'Chat', 230)
    name('ui.maxContextSize', second, y + 34)
    switch(second, y + 51)
    figure.field(second + 36, y + 44, 70, BUTTON_HEIGHT, '100')
    figure.text(second + 180, y + 34, word('ui.maxOutputTokens'), 13, None, '600')
    switch(second + 180, y + 51, False)
    figure.field(second + 216, y + 44, 70, BUTTON_HEIGHT, '4000')
    # The model, and how it reasons
    used = name('ui.model', first, y + 108)
    switch(first + used + 16, y + 97, False)
    figure.text(first + used + 52, y + 108, word('ui.showAllModels'), 12, quiet)
    blank_select(first, y + 118, 230, 130)
    name('ui.reasoningEffort', second, y + 108)
    blank_select(second, y + 118, 140, 60)
    switch(second + 180, y + 125)
    figure.text(second + 216, y + 137, word('ui.showThinking'), 13)
    # Temperature
    name('ui.temperature', first, y + 184)
    figure.add('<rect x="%d" y="%d" width="230" height="5" rx="2.5" fill="%s"/><circle cx="%d" cy="%d" r="7" fill="%s"/>'
               % (first, y + 200, line, first + 69, y + 202, color('pal-accent-strong')))
    # The initial prompt, folded
    figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s"/>' % (x, y + 232, x + width, y + 232, line))
    figure.icon('fas', 'fa-chevron-right', first, y + 251, 11, quiet)
    figure.callout(first - 22, y + 258)
    figure.text(first + 18, y + 262, word('ui.initialPromptAssistant'), 13, None, '600')
    figure.lines(first + 18, y + 280, [width - 150, width - 260])
    # Start
    figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s"/>' % (x, y + 322, x + width, y + 322, line))
    figure.button(first, y + 334, 'primary', 'fas', 'fa-rocket', label(table, 'ui.session.startSession'), mark=False)
    figure.callout(first - 22, y + 348)
    figure.grow(x + width, y + 372)
    return figure


def speech_panel(table, color, title):
    """The Speech panel of the menu."""
    figure = Figure(color, title)
    page_keys(['ui.speech', 'ui.speechToTextModel', 'ui.textToSpeechProvider', 'ui.webSpeechVoice', 'ui.ttsSpeed'])
    word = lambda key: plain(label(table, key))  # noqa: E731
    line = color('pal-grey-line')
    x, y, width = 20, 20, 400
    figure.add('<rect x="%d" y="%d" width="%d" height="330" rx="6" fill="#ffffff" stroke="%s"/>' % (x, y, width, line))
    figure.icon('fas', 'fa-comment-dots', x + 44, y + 16, 15, color('pal-amber-mid'))
    figure.text(x + 68, y + 29, word('ui.speech'), 15, None, '600')
    row = y + 62
    for key in ('ui.speechToTextModel', 'ui.textToSpeechProvider', 'ui.webSpeechVoice'):
        figure.text(x + 44, row, word(key), 13, None, '600')
        figure.callout(x + 22, row - 4)
        figure.field(x + 44, row + 10, width - 64, BUTTON_HEIGHT)
        figure.add('<rect x="%d" y="%d" width="140" height="8" rx="4" fill="%s"/>' % (x + 54, row + 20, line))
        figure.add('<path d="M%.1f %.1f l4 5 l4 -5 z" fill="%s"/>' % (x + width - 38, row + 22, color('pal-grey-strong')))
        row += 72
    figure.text(x + 44, row, '%s (1.00)' % word('ui.ttsSpeed'), 13, None, '600')
    figure.callout(x + 22, row - 4)
    figure.add('<rect x="%d" y="%d" width="%d" height="5" rx="2.5" fill="%s"/><circle cx="%d" cy="%d" r="7" fill="%s"/>'
               % (x + 44, row + 18, width - 64, line, x + 44 + (width - 64) // 2, row + 20, color('pal-accent-strong')))
    figure.grow(x + width, y + 330)
    return figure


def web_interface(table, color, title):
    """The whole page: where each part of it is."""
    figure = Figure(color, title)
    page_keys(['ui.configSummaryLabel', 'ui.mainTabs.session', 'ui.dialog'])
    word = lambda key: plain(label(table, key))  # noqa: E731
    ink, quiet, line = color('text-primary'), color('pal-grey-text'), color('pal-grey-line')
    blue, amber = color('pal-accent-strong'), color('pal-amber-mid')

    def panel(px, py, w, h):
        figure.add('<rect x="%d" y="%d" width="%d" height="%d" rx="6" fill="#ffffff" stroke="%s"/>' % (px, py, w, h, line))

    # The bar at the top
    panel(20, 34, 860, 46)
    figure.add('<rect x="34" y="45" width="24" height="24" rx="5" fill="%s"/>' % amber)
    used = figure.text(68, 63, 'Monadic', 17, ink, '600')
    figure.text(68 + used + 5, 63, 'Chat', 17, color('pal-amber-strong'), '700')
    figure.callout(90, 21)
    status = word('ui.messages.readyForInput')
    sw = text_width(status) + 46
    figure.add('<rect x="%.1f" y="45" width="%.1f" height="24" rx="4" fill="%s" stroke="%s"/>'
               % (820 - sw, sw, color('pal-grey-soft'), line))
    figure.icon('fas', 'fa-circle-check', 830 - sw, 51, 12, color('pal-green-strong'))
    figure.text(848 - sw, 62, status)
    figure.callout(820 - sw / 2, 21)
    figure.add('<rect x="832" y="45" width="36" height="24" rx="4" fill="#ffffff" stroke="%s"/>' % blue)
    figure.icon('fas', 'fa-bars', 844, 51, 12, blue)
    figure.callout(850, 21)

    # The conversation's side
    figure.add('<rect x="20" y="106" width="520" height="40" rx="6" fill="%s"/>' % line)
    tx = 28
    for key, chosen in (('ui.configSummaryLabel', False), ('ui.mainTabs.session', True)):
        text = word(key)
        w = text_width(text, 12, '600') + 20
        if chosen:
            figure.add('<rect x="%.1f" y="112" width="%.1f" height="28" rx="5" fill="#ffffff"/>' % (tx, w))
        figure.text(tx + w / 2, 131, text, 12, ink if chosen else quiet, '600' if chosen else None, 'middle')
        tx += w + 4
    tx += 10
    tx += figure.icon('fas', 'fa-comment', tx, 119, 13, ink) + 6
    tx += figure.text(tx, 131, 'Chat', 13, ink, '700') + 10
    figure.add('<rect x="%.1f" y="122" width="90" height="8" rx="4" fill="%s"/>' % (tx, color('pal-grey-mid')))
    figure.callout(520, 93)

    panel(20, 158, 520, 300)
    used = figure.icon('fas', 'fa-comments', 36, 172, 14, amber)
    figure.text(36 + used + 8, 184, word('ui.dialog'), 14, None, '600')
    figure.callout(520, 172)
    for top, icon, name, tint, ground in ((198, 'fa-face-smile', 'User', color('color-user'), color('bg-card-user')),
                                         (310, 'fa-robot', 'Assistant', color('color-assistant'), color('bg-card-assistant'))):
        figure.add('<rect x="36" y="%d" width="488" height="96" rx="6" fill="%s" stroke="%s"/>' % (top, ground, line))
        figure.add('<path d="M42 %d H518 A6 6 0 0 1 524 %d V%d H36 V%d A6 6 0 0 1 42 %d Z" fill="#ffffff"/>'
                   % (top, top + 6, top + 32, top + 6, top))
        figure.add('<rect x="36" y="%d" width="488" height="96" rx="6" fill="none" stroke="%s"/>' % (top, line))
        used = figure.icon('fas', icon, 48, top + 9, 14, tint)
        figure.text(48 + used + 8, top + 21, name, 13, tint, '700')
        figure.lines(50, top + 48, [430, 330] if name == 'User' else [440, 380])

    figure.field(20, 470, 520, 56)
    figure.callout(520, 484)
    bx = 20
    for w, fill in ((70, amber), (130, amber), (92, amber), (84, amber), (92, amber)):
        figure.add('<rect x="%d" y="538" width="%d" height="26" rx="4" fill="%s"/>' % (bx, w, fill))
        bx += w + 8
    figure.add('<rect x="20" y="576" width="70" height="26" rx="4" fill="%s"/>' % blue)
    figure.add('<rect x="98" y="576" width="76" height="26" rx="4" fill="%s"/>' % color('pal-grey-strong'))

    # The side column
    figure.add('<rect x="560" y="106" width="320" height="40" rx="6" fill="%s"/>' % line)
    tx = 568
    for i, key in enumerate(side_tabs()):
        text = label(table, key)
        w = text_width(text, 12, '600') + 20
        if i == 0:
            figure.add('<rect x="%.1f" y="112" width="%.1f" height="28" rx="5" fill="#ffffff"/>' % (tx, w))
        figure.text(tx + w / 2, 131, text, 12, ink if i == 0 else quiet, '600' if i == 0 else None, 'middle')
        tx += w + 4
    figure.callout(860, 93)
    for top, h in ((158, 150), (320, 110), (442, 160)):
        panel(560, top, 320, h)
        figure.add('<rect x="576" y="%d" width="120" height="10" rx="5" fill="%s"/>' % (top + 16, color('pal-grey-mid')))
        figure.lines(576, top + 42, [270, 220, 250][:max(1, (h - 50) // 22)])
    figure.callout(860, 172)
    figure.grow(880, 602)
    return figure


# ---- the desktop app --------------------------------------------------------
def app_translations(language):
    with open(os.path.join(ROOT, 'app', 'translations', '%s.json' % language), encoding='utf-8') as f:
        return json.load(f)


def app_menus():
    """The desktop app's menus as app/main.js builds them: [(key, [item key | None for a separator])]."""
    with open(os.path.join(ROOT, 'app', 'main.js'), encoding='utf-8') as f:
        source = f.read()
    start = source.index('const menu = Menu.buildFromTemplate([')
    template = source[start:source.index('\n  ]);', start)]
    heads = list(re.finditer(r"label: i18n\.t\('menu\.(\w+)'\),\s*\n\s*submenu: \[", template))
    if not heads:
        raise SystemExit('app/main.js no longer builds its menus as the menu figures read them')
    menus = []
    for i, head in enumerate(heads):
        chunk = template[head.end():heads[i + 1].start() if i + 1 < len(heads) else len(template)]
        items = [m.group(1) or m.group(3) and 'role:' + m.group(3)
                 for m in re.finditer(r"label: i18n\.t\('menu\.(\w+)'\)|(type: 'separator')|role: '(\w+)'", chunk)]
        while items and items[-1] is None:
            items.pop()
        menus.append((head.group(1), items))
    return menus


def desktop_menu(opened):
    def draw(table, color, title, language):
        """The menu bar with one menu open."""
        words = app_translations(language)['menu']
        # The figure's title names the menu as the app does
        figure = Figure(color, {'en': 'The %s menu', 'ja': '%s メニュー'}[language] % words[opened])
        menus = app_menus()
        names = [key for key, _ in menus]
        if opened not in names:
            raise SystemExit('app/main.js has no %s menu' % opened)
        ink, quiet, line = color('text-primary'), color('pal-grey-text'), color('pal-grey-line')
        items = [item for item in dict(menus)[opened] if item is None or not item.startswith('role:')]
        labels = [words[item] for item in items if item]
        width = max(text_width(text) for text in labels) + 56
        # The bar
        x, y = 20, 20
        bar = []
        cx = x + 10
        for key in names:
            text = words[key]
            w = text_width(text, 13, '600') + 20
            bar.append((key, text, cx, w))
            cx += w + 2
        bar_width = max(cx + 8 - x, 0)
        open_x = [bx for key, _, bx, _ in bar if key == opened][0]
        total = max(bar_width, open_x - x + width + 20)
        figure.add('<rect x="%d" y="%d" width="%.1f" height="32" rx="6" fill="#ffffff" stroke="%s"/>' % (x, y, total, line))
        for key, text, bx, w in bar:
            if key == opened:
                figure.add('<rect x="%.1f" y="%d" width="%.1f" height="24" rx="4" fill="%s"/>' % (bx, y + 4, w, line))
            figure.text(bx + w / 2, y + 21, text, 13, ink, '600' if key == opened else None, 'middle')
        # The open menu
        height = sum(11 if item is None else 26 for item in items) + 12
        top = y + 38
        figure.add('<rect x="%.1f" y="%d" width="%.1f" height="%d" rx="6" fill="#ffffff" stroke="%s"/>'
                   % (open_x, top, width, height, color('pal-grey-mid')))
        cy = top + 6
        for item in items:
            if item is None:
                figure.add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s"/>'
                           % (open_x + 10, cy + 5.5, open_x + width - 10, cy + 5.5, line))
                cy += 11
            else:
                figure.text(open_x + 16, cy + 18, words[item])
                cy += 26
        figure.grow(x + total, top + height)
        return figure
    return draw


# ---- the architecture ---------------------------------------------------------
SERVICES = ['ruby', 'python', 'selenium', 'qdrant', 'embeddings', 'privacy', 'extractor']


def services():
    """The services of docker/services, which the diagram must know one by one."""
    folder = os.path.join(ROOT, 'docker', 'services')
    found = sorted(name for name in os.listdir(folder)
                   if os.path.exists(os.path.join(folder, name, 'Dockerfile')))
    if found != sorted(SERVICES):
        raise SystemExit('docker/services has %s; the architecture figure draws %s' % (found, sorted(SERVICES)))
    return SERVICES


def providers():
    """The chat providers' names as the app shows them, the local one apart."""
    source = read('lib', 'monadic', 'dsl', 'provider_config.rb')
    table = source[source.index('PROVIDER_INFO = {'):]
    names = re.findall(r'"([a-z]+)" => \{.*?display_group: \'([^\']+)\'', table, re.S)
    cloud = [name for key, name in names if key != 'ollama']
    if not cloud or 'ollama' not in dict(names):
        raise SystemExit('provider_config.rb no longer lists the providers as the architecture figure reads them')
    return cloud, dict(names)['ollama']


ARCHITECTURE = {
    'en': {
        'computer': 'Your computer', 'desktop': 'Desktop app', 'desktop_1': 'Starts and stops the containers',
        'desktop_2': 'Settings and API keys', 'web': 'Web interface', 'conversation': 'Conversation',
        'local': 'Local models', 'local_1': 'Outside Docker, on your GPU',
        'local_2': 'No API key needed', 'docker': 'Docker containers', 'server': 'Monadic Chat server',
        'apps': 'Apps', 'adapters': 'Model adapters', 'tools': 'Tools', 'mcp': 'MCP server',
        'python': 'Runs code · JupyterLab', 'selenium': 'A browser for the apps',
        'qdrant': 'Vector database', 'embeddings': 'Turns text into vectors',
        'privacy': 'Finds names to hide', 'extractor': 'Reads PDFs (optional)',
        'shared': 'Shared folder', 'shared_note': 'your files and what the apps make',
        'cloud': 'Language model APIs', 'cloud_note': 'chat · speech · images · video',
        'requests': 'API requests',
    },
    'ja': {
        'computer': 'あなたのコンピューター', 'desktop': 'デスクトップアプリ', 'desktop_1': 'コンテナの起動と停止',
        'desktop_2': '設定と API キー', 'web': 'Web インターフェース', 'conversation': '会話',
        'local': 'ローカルのモデル', 'local_1': 'Docker の外で、GPU を使って動く',
        'local_2': 'API キーは不要', 'docker': 'Docker コンテナ', 'server': 'Monadic Chat サーバー',
        'apps': 'アプリ', 'adapters': 'モデルとの接続', 'tools': 'ツール', 'mcp': 'MCP サーバー',
        'python': 'コード実行・JupyterLab', 'selenium': 'アプリ用のブラウザー',
        'qdrant': 'ベクトルデータベース', 'embeddings': 'テキストをベクトルに変換',
        'privacy': '伏せる名前を見つける', 'extractor': 'PDF の読み取り（任意）',
        'shared': '共有フォルダ', 'shared_note': 'あなたのファイルと、アプリが作るもの',
        'cloud': '言語モデルの API', 'cloud_note': 'チャット・音声・画像・動画',
        'requests': 'API リクエスト',
    },
}
SERVICE_ICONS = {'python': ('fab', 'fa-python'), 'selenium': ('fab', 'fa-chrome'), 'qdrant': ('fas', 'fa-database'),
                 'embeddings': ('fas', 'fa-diagram-project'), 'privacy': ('fas', 'fa-user-secret'),
                 'extractor': ('fas', 'fa-file-lines')}


def architecture(table, color, title, language):
    """The whole system: what runs on the computer, and what is asked of the cloud."""
    figure = Figure(color, title)
    word = ARCHITECTURE[language]
    ink, quiet, line = color('text-primary'), color('pal-grey-text'), color('pal-grey-line')
    blue, yellow, brown, green = (color('pal-accent-strong'), color('pal-amber-mid'), color('pal-amber-strong'),
                                  color('pal-green-strong'))

    def heading(x, y, name, icon, tint, size=15, fill=None, style='fas'):
        x += figure.icon(style, icon, x, y - 13, size, tint) + 8
        figure.text(x, y, name, size, fill or ink, '700')

    def card(x, y, w, h, name, icon, tint, note=None, ground='#ffffff', style='fas'):
        """A part: white, with its kind's color down the whole of its left edge."""
        figure.add('<rect x="%d" y="%d" width="%d" height="%d" rx="6" fill="%s"/>' % (x, y, w, h, tint))
        figure.add('<path d="M%d %d H%d A6 6 0 0 1 %d %d V%d A6 6 0 0 1 %d %d H%d Z" fill="%s"/>'
                   % (x + 5, y, x + w - 6, x + w, y + 6, y + h - 6, x + w - 6, y + h, x + 5, ground))
        figure.add('<rect x="%d" y="%d" width="%d" height="%d" rx="6" fill="none" stroke="%s"/>' % (x, y, w, h, line))
        heading(x + 18, y + 27, name, icon, tint, 14, None, style)
        for i, text in enumerate(note or []):
            figure.text(x + 18, y + 48 + i * 18, text, 12, ink if i == 0 and len(note) > 2 else quiet)

    def chip(x, y, text, stroke, fill, width=None, weight=None):
        w = width or text_width(text, 12, weight) + 16
        figure.add('<rect x="%.1f" y="%d" width="%.1f" height="24" rx="12" fill="none" stroke="%s"/>' % (x, y, w, stroke))
        figure.text(x + w / 2, y + 16.5, text, 12, fill, weight, 'middle')
        return w

    def arrow(x1, y1, x2, y2, both=False, dashed=False):
        figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1.5"%s marker-end="url(#arrow)"%s/>'
                   % (x1, y1, x2, y2, color('pal-grey-strong'), ' stroke-dasharray="5 4"' if dashed else '',
                      ' marker-start="url(#arrow-back)"' if both else ''))

    cloud, local = providers()
    # Your computer: what you use, at the top
    figure.add('<rect x="20" y="20" width="800" height="664" rx="12" fill="%s" stroke="%s"/>' % (color('pal-grey-soft'), line))
    heading(38, 48, word['computer'], 'fa-laptop', quiet, 15, quiet)
    card(40, 64, 250, 96, word['desktop'], 'fa-desktop', green, [word['desktop_1'], word['desktop_2']])
    card(310, 64, 490, 96, word['web'], 'fa-window-maximize', green)
    cx = 328
    for text in [word['conversation'], label(table, 'ui.sidePane.workScreen'), label(table, 'ui.sidePane.files'),
                 label(table, 'ui.sidePane.history'),
                 re.sub(r'<[^>]+>\s*', '', label(table, 'ui.knowledgeBase')).strip()]:
        cx += chip(cx, 118, text, green, color('pal-green-text')) + 6

    # Docker: the services on the left, the server on the right (it faces the cloud)
    figure.add('<rect x="40" y="210" width="760" height="304" rx="10" fill="#ffffff" stroke="%s" stroke-width="1.5"/>' % blue)
    heading(58, 238, word['docker'], 'fa-docker', blue, 15, color('pal-accent-text'), 'fab')
    known = services()
    for i, name in enumerate(s for s in known if s != 'ruby'):
        col, row = i % 2, i // 2
        style, icon = SERVICE_ICONS[name]
        card(60 + col * 188, 258 + row * 80, 176, 68, name.capitalize(), icon, blue,
             [word[name]], color('pal-grey-soft'), style)

    figure.add('<rect x="480" y="258" width="300" height="228" rx="8" fill="#ffffff" stroke="%s" stroke-width="1.5"/>' % brown)
    heading(498, 286, word['server'], 'fa-server', brown)
    py = 302
    for i, key in enumerate(['apps', 'adapters', 'tools']):
        figure.add('<rect x="500" y="%d" width="260" height="32" rx="6" fill="%s"/>' % (py, yellow))
        figure.text(630, py + 21, word[key], 13, ink, '700', 'middle')
        if i < 2:
            arrow(630, py + 34, 630, py + 50)
        py += 52
    figure.text(630, 466, word['mcp'], 12, quiet, None, 'middle')
    # The language the server is written in, as a tab on the box's edge
    ruby = color('pal-red-strong')
    figure.add('<rect x="496" y="473" width="88" height="26" rx="13" fill="#ffffff" stroke="%s" stroke-width="1.5"/>' % ruby)
    figure.icon('fas', 'fa-gem', 510, 479, 13, ruby)
    figure.text(530, 491, 'Ruby', 13, ink, '700')
    arrow(428, 372, 478, 372, both=True)             # the server uses the services

    # Below: the folder both sides share, and models that run here
    figure.add('<rect x="40" y="564" width="500" height="100" rx="6" fill="#ffffff" stroke="%s" stroke-dasharray="6 4"/>'
               % color('pal-grey-mid'))
    heading(58, 594, word['shared'], 'fa-folder-open', brown, 15)
    figure.text(58, 618, word['shared_note'], 12, quiet)
    # The folder's two names, joined by a drawn mark (a character's shape varies with the font)
    px = 58 + figure.text(58, 638, '~/monadic/data', 12, quiet) + 8
    px += figure.icon('fas', 'fa-right-left', px, 628, 11, quiet) + 8
    figure.text(px, 638, '/monadic/data', 12, quiet)
    card(560, 564, 240, 100, local, 'fa-microchip', brown, [word['local'], word['local_1'], word['local_2']])

    # Lines: each one straight, none over a box, and long enough to show its line
    arrow(165, 162, 165, 208)                        # the desktop app runs the containers
    arrow(630, 162, 630, 256, both=True)             # the page and the server
    arrow(240, 516, 240, 562, both=True, dashed=True)  # the containers and the shared folder
    arrow(680, 488, 680, 562, both=True)             # the server and local models

    # The cloud, beside the server and outside the computer's frame
    figure.add('<rect x="880" y="210" width="270" height="304" rx="10" fill="#ffffff" stroke="%s" stroke-width="1.5"/>'
               % color('pal-grey-strong'))
    heading(902, 242, word['cloud'], 'fa-cloud', color('pal-grey-strong'), 15)
    figure.text(902, 264, word['cloud_note'], 12, quiet)
    step = min(30, (514 - 16 - 280) // len(cloud))
    for i, name in enumerate(cloud):
        chip(902, 282 + i * step, name, color('pal-grey-mid'), ink, 226, '700')
    arrow(782, 372, 878, 372, both=True)             # API requests

    figure.grow(1150, 684)
    head = color('pal-grey-strong')
    figure.extra_defs = (
        '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="12" '
        'markerHeight="12" orient="auto"><path d="M0 1 L10 5 L0 9 z" fill="%s"/></marker>'
        '<marker id="arrow-back" viewBox="0 0 10 10" refX="1" refY="5" markerUnits="userSpaceOnUse" markerWidth="12" '
        'markerHeight="12" orient="auto"><path d="M10 1 L0 5 L10 9 z" fill="%s"/></marker>' % (head, head))
    figure.ground = '#ffffff'
    return figure


FIGURES = {
    'input-buttons': (input_buttons, {'en': 'Buttons under the message box', 'ja': 'メッセージ入力欄の下のボタン'}),
    'message-buttons': (message_buttons, {'en': "Buttons of an assistant's card", 'ja': 'アシスタントのカードのボタン'}),
    'knowledge-base': (knowledge_base, {'en': 'Knowledge Base panel', 'ja': 'Knowledge Base のパネル'}),
    'live-conversation': (live_conversation, {'en': 'Live Conversation controls', 'ja': 'Live Conversation の操作欄'}),
    'side-column': (side_column, {'en': 'Tabs of the side column', 'ja': '右側の列のタブ'}),
    'url-dialog': (url_dialog, {'en': 'The Open URL dialog', 'ja': 'URL を開くダイアログ'}),
    'role-selector': (role_selector, {'en': 'The Role selector', 'ja': '役割の選択'}),
    'voice-input': (voice_input, {'en': 'Voice input', 'ja': '音声入力'}),
    'web-interface': (web_interface, {'en': 'The web interface', 'ja': 'Web インターフェース'}),
    'system-settings': (system_settings, {'en': 'System settings', 'ja': 'システム設定'}),
    'speech-panel': (speech_panel, {'en': 'Speech panel', 'ja': 'Speech パネル'}),
    'attachments': (attachments, {'en': 'Files attached to a message', 'ja': 'メッセージに添付したファイル'}),
    'menu-file': (desktop_menu('file'), {'en': 'The File menu', 'ja': 'File メニュー'}),
    'menu-actions': (desktop_menu('actions'), {'en': 'The Actions menu', 'ja': 'Actions メニュー'}),
    'menu-open': (desktop_menu('open'), {'en': 'The Open menu', 'ja': 'Open メニュー'}),
    'architecture': (architecture, {'en': 'Monadic Chat architecture', 'ja': 'Monadic Chat の構成'}),
}


def main():
    tables, color = translations(LANGUAGES), tokens()
    for name, (draw, titles) in FIGURES.items():
        for language in LANGUAGES:
            os.makedirs(OUT[language], exist_ok=True)
            path = os.path.join(OUT[language], '%s.svg' % name)
            with open(path, 'w', encoding='utf-8') as f:
                arguments = (tables[language], color, titles[language])
                if draw is architecture or draw.__name__ == 'draw':
                    arguments += (language,)
                f.write(draw(*arguments).svg())
            print(os.path.relpath(path, ROOT))


if __name__ == '__main__':
    main()
