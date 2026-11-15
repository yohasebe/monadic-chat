"""Generate the schematic figures of the web UI (docs/assets/images/figures/ and
docs/ja/assets/images/figures/, one set for each language of the documentation).

A figure's layout is written here. What it shows is read from the page:
- a control's label key, icon and kind from the page's markup
  (docker/services/ruby/views/index.erb and public/js/monadic/*.js),
- the label's text from the page's translations (public/js/i18n/translations.js),
- the colors from the page's tokens (public/css/tokens.css),
- an icon's outline from the icon font the page loads (public/vendor/webfonts).
A control that is renamed changes its figure; one that is removed stops this
script.

Run from the repository root:

    python3 scripts/generate_ui_figures.py

Needs python3 with fontTools, and node (for the translations and to read the
compressed font). Edit this file, not the generated SVGs.
"""
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
             'far': 'fa-regular-400.woff2', 'fa-regular': 'fa-regular-400.woff2'}
    fonts = {}

    def __init__(self):
        css = read('public', 'vendor', 'css', 'all.min.css')
        # One rule may name several icons: .fa-a,.fa-b{--fa:"\f000"}
        self.codes = {}
        for selectors, code in re.findall(r'((?:\.fa-[a-z0-9-]+,?)+)\{--fa:"\\([0-9a-f]+)"', css):
            for name in selectors.strip(',').split(','):
                self.codes[name[1:]] = int(code, 16)
        self.used = {}

    def use(self, style, name):
        key = '%s-%s' % (self.FILES[style].split('-')[1], name[3:])
        if key not in self.used:
            font = Icons.fonts.setdefault(
                self.FILES[style], TTFont(os.path.join(RUBY, 'public', 'vendor', 'webfonts', self.FILES[style])))
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


def text_width(text, size=TEXT):
    return sum(size * (1.0 if ord(ch) > 0x2E7F else 0.56) for ch in text)


class Figure:
    def __init__(self, color, title):
        self.color, self.title = color, title
        self.icons = Icons()
        self.parts = []
        self.number = 0
        self.width = self.height = 0

    def add(self, svg):
        self.parts.append(svg)

    def grow(self, right, bottom):
        self.width, self.height = max(self.width, right), max(self.height, bottom)

    def text(self, x, y, text, size=TEXT, fill=None, weight=None, anchor=None):
        self.add('<text x="%.1f" y="%.1f" font-size="%d" fill="%s"%s%s>%s</text>' % (
            x, y, size, fill or self.color('text-primary'),
            ' font-weight="%s"' % weight if weight else '', ' text-anchor="%s"' % anchor if anchor else '', escape(text)))
        return text_width(text, size)

    def icon(self, style, name, x, y, size=TEXT, fill=None):
        key = self.icons.use(style, name)
        width = size * self.icons.ratio(key)
        self.add('<use href="#i-%s" x="%.1f" y="%.1f" width="%.1f" height="%d" fill="%s"/>'
                 % (key, x, y, width, size, fill or self.color('text-primary')))
        return width

    def callout(self, cx, cy):
        """A numbered mark; the document's list says what each number is."""
        self.number += 1
        self.add('<circle cx="%.1f" cy="%.1f" r="9" fill="%s"/>' % (cx, cy, self.color('pal-red-strong')))
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
        width = pad + icon_width + 5 + text_width(text) + pad
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
        ground = '<rect width="%.0f" height="%.0f" rx="8" fill="%s"/>' % (width, height, self.color('pal-grey-soft'))
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" viewBox="0 0 %.0f %.0f" '
                'font-family="%s">\n  <title>%s</title>\n  <defs>\n%s\n  </defs>\n  %s\n</svg>\n'
                % (width, height, width, height, FONT, escape(self.title), self.icons.symbols(),
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
    figure.add('<rect x="%d" y="%d" width="%d" height="40" rx="6" fill="%s"/>' % (x, y, width, color('pal-grey-soft')))
    figure.add('<rect x="%d" y="%d" width="%d" height="78" fill="%s"/>' % (x + 1, y + 40, width - 2, color('bg-card-assistant')))
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
    figure.add('<rect x="%d" y="%d" width="%d" height="166" rx="6" fill="#ffffff"/>' % (x, y, width))
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
    figure.add('<rect x="%d" y="%d" width="%d" height="120" rx="6" fill="#ffffff"/>' % (x, y + 48, panel_width))
    figure.lines(x + 16, y + 66, [panel_width - 60, panel_width - 140, panel_width - 90, panel_width - 200])
    figure.grow(x + panel_width, y + 168)
    return figure


FIGURES = {
    'input-buttons': (input_buttons, {'en': 'Buttons under the message box', 'ja': 'メッセージ入力欄の下のボタン'}),
    'message-buttons': (message_buttons, {'en': "Buttons of an assistant's card", 'ja': 'アシスタントのカードのボタン'}),
    'knowledge-base': (knowledge_base, {'en': 'Knowledge Base panel', 'ja': 'Knowledge Base のパネル'}),
    'live-conversation': (live_conversation, {'en': 'Live Conversation controls', 'ja': 'Live Conversation の操作欄'}),
    'side-column': (side_column, {'en': 'Tabs of the side column', 'ja': '右側の列のタブ'}),
}


def main():
    tables, color = translations(LANGUAGES), tokens()
    for name, (draw, titles) in FIGURES.items():
        for language in LANGUAGES:
            os.makedirs(OUT[language], exist_ok=True)
            path = os.path.join(OUT[language], '%s.svg' % name)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(draw(tables[language], color, titles[language]).svg())
            print(os.path.relpath(path, ROOT))


if __name__ == '__main__':
    main()
