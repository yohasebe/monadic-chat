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
             'far': 'fa-regular-400.woff2', 'fa-regular': 'fa-regular-400.woff2'}
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


def text_width(text, size=TEXT):
    return sum(size * (1.0 if ord(ch) > 0x2E7F else 0.56) for ch in text)


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
        ground = '<rect width="%.0f" height="%.0f" rx="8" fill="%s"/>' % (
            width, height, self.ground or self.color('pal-grey-soft'))
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" viewBox="0 0 %.0f %.0f" '
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
        'local': 'Local models', 'docker': 'Docker containers', 'server': 'Monadic Chat server',
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
        'local': 'ローカルのモデル', 'docker': 'Docker コンテナ', 'server': 'Monadic Chat サーバー',
        'apps': 'アプリ', 'adapters': 'モデルとの接続', 'tools': 'ツール', 'mcp': 'MCP サーバー',
        'python': 'コードの実行・JupyterLab', 'selenium': 'アプリが操作するブラウザー',
        'qdrant': 'ベクトルデータベース', 'embeddings': 'テキストをベクトルに変換',
        'privacy': '伏せる名前を見つける', 'extractor': 'PDF の読み取り（任意）',
        'shared': '共有フォルダ', 'shared_note': 'あなたのファイルと、アプリが作るもの',
        'cloud': '言語モデルの API', 'cloud_note': 'チャット・音声・画像・動画',
        'requests': 'API リクエスト',
    },
}
SERVICE_ICONS = {'python': 'fa-code', 'selenium': 'fa-globe', 'qdrant': 'fa-database',
                 'embeddings': 'fa-diagram-project', 'privacy': 'fa-user-secret', 'extractor': 'fa-file-lines'}


def architecture(table, color, title, language):
    """The whole system: what runs on the computer, and what is asked of the cloud."""
    figure = Figure(color, title)
    word = ARCHITECTURE[language]
    ink, quiet, line = color('text-primary'), color('pal-grey-text'), color('pal-grey-line')
    blue, yellow, brown, green = (color('pal-accent-strong'), color('pal-amber-mid'), color('pal-amber-strong'),
                                  color('pal-green-strong'))

    def heading(x, y, name, icon, tint, size=15, fill=None):
        x += figure.icon('fas', icon, x, y - 13, size, tint) + 8
        figure.text(x, y, name, size, fill or ink, '700')

    def card(x, y, w, h, name, icon, tint, note=None, ground='#ffffff'):
        """A part: white, with its kind's color as a bar on the left."""
        figure.add('<rect x="%d" y="%d" width="%d" height="%d" rx="6" fill="%s" stroke="%s"/>' % (x, y, w, h, ground, line))
        figure.add('<rect x="%d" y="%d" width="4" height="%d" rx="2" fill="%s"/>' % (x, y + 8, h - 16, tint))
        heading(x + 18, y + 27, name, icon, tint, 14)
        for i, text in enumerate(note or []):
            figure.text(x + 18, y + 48 + i * 18, text, 12, quiet)

    def chip(x, y, text, stroke, fill, width=None):
        w = width or text_width(text, 12) + 22
        figure.add('<rect x="%.1f" y="%d" width="%.1f" height="24" rx="12" fill="none" stroke="%s"/>' % (x, y, w, stroke))
        figure.text(x + w / 2, y + 16.5, text, 12, fill, None, 'middle')
        return w

    def arrow(x1, y1, x2, y2, both=False, dashed=False):
        figure.add('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="1.5"%s marker-end="url(#arrow)"%s/>'
                   % (x1, y1, x2, y2, color('pal-grey-strong'), ' stroke-dasharray="5 4"' if dashed else '',
                      ' marker-start="url(#arrow-back)"' if both else ''))

    cloud, local = providers()
    # Your computer: what you use, at the top
    figure.add('<rect x="20" y="20" width="800" height="660" rx="12" fill="%s" stroke="%s"/>' % (color('pal-grey-soft'), line))
    heading(38, 48, word['computer'], 'fa-laptop', quiet, 15, quiet)
    card(40, 64, 220, 96, word['desktop'], 'fa-desktop', blue, [word['desktop_1'], word['desktop_2']])
    card(280, 64, 520, 96, word['web'], 'fa-window-maximize', blue)
    cx = 298
    for text in [word['conversation'], label(table, 'ui.sidePane.workScreen'), label(table, 'ui.sidePane.files'),
                 label(table, 'ui.sidePane.history'),
                 re.sub(r'<[^>]+>\s*', '', label(table, 'ui.knowledgeBase')).strip()]:
        cx += chip(cx, 118, text, blue, color('pal-accent-text')) + 6

    # Docker: the services on the left, the server on the right (it faces the cloud)
    figure.add('<rect x="40" y="210" width="760" height="304" rx="10" fill="#ffffff" stroke="%s" stroke-width="1.5"/>' % green)
    heading(58, 238, word['docker'], 'fa-cubes', green, 15, color('pal-green-text'))
    known = services()
    for i, name in enumerate(s for s in known if s != 'ruby'):
        col, row = i % 2, i // 2
        card(60 + col * 188, 258 + row * 80, 176, 68, name.capitalize(), SERVICE_ICONS[name], green,
             [word[name]], color('pal-grey-soft'))

    figure.add('<rect x="480" y="258" width="300" height="228" rx="8" fill="#ffffff" stroke="%s" stroke-width="2"/>' % brown)
    heading(498, 286, word['server'], 'fa-server', brown)
    figure.text(764, 286, 'Ruby', 12, quiet, None, 'end')
    py = 302
    for i, key in enumerate(['apps', 'adapters', 'tools']):
        figure.add('<rect x="500" y="%d" width="260" height="32" rx="6" fill="%s"/>' % (py, yellow))
        figure.text(630, py + 21, word[key], 13, ink, '700', 'middle')
        if i < 2:
            arrow(630, py + 34, 630, py + 50)
        py += 52
    figure.text(630, 474, word['mcp'], 12, quiet, None, 'middle')
    arrow(428, 372, 478, 372, both=True)             # the server uses the services

    # Below: the folder both sides share, and models that run here
    figure.add('<rect x="40" y="560" width="500" height="100" rx="6" fill="#ffffff" stroke="%s" stroke-dasharray="6 4"/>'
               % color('pal-grey-mid'))
    heading(58, 590, word['shared'], 'fa-folder-open', brown, 15)
    figure.text(58, 614, word['shared_note'], 12, quiet)
    figure.text(58, 634, '~/monadic/data  ⇄  /monadic/data', 12, quiet)
    card(560, 560, 240, 100, local, 'fa-microchip', brown, [word['local']])

    # Lines: each one straight, none over a box, and long enough to show its line
    arrow(150, 162, 150, 208)                        # the desktop app runs the containers
    arrow(630, 162, 630, 256, both=True)             # the page and the server
    arrow(240, 516, 240, 558, both=True, dashed=True)  # the containers and the shared folder
    arrow(680, 488, 680, 558, both=True)             # the server and local models

    # The cloud, beside the server: outside the computer, so drawn dark
    figure.add('<rect x="880" y="210" width="230" height="304" rx="10" fill="%s"/>' % ink)
    heading(898, 240, word['cloud'], 'fa-cloud', yellow, 15, '#ffffff')
    figure.text(898, 262, word['cloud_note'], 12, '#c9ced4')
    step = min(30, (514 - 16 - 280) // len(cloud))
    for i, name in enumerate(cloud):
        chip(898, 280 + i * step, name, '#8b939b', '#ffffff', 194)
    arrow(782, 372, 878, 372, both=True)             # API requests

    figure.grow(1110, 680)
    head = color('pal-grey-strong')
    figure.extra_defs = (
        '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerUnits="userSpaceOnUse" markerWidth="9" '
        'markerHeight="9" orient="auto"><path d="M0 1 L10 5 L0 9 z" fill="%s"/></marker>'
        '<marker id="arrow-back" viewBox="0 0 10 10" refX="1" refY="5" markerUnits="userSpaceOnUse" markerWidth="9" '
        'markerHeight="9" orient="auto"><path d="M10 1 L0 5 L10 9 z" fill="%s"/></marker>' % (head, head))
    figure.ground = '#ffffff'
    return figure


FIGURES = {
    'input-buttons': (input_buttons, {'en': 'Buttons under the message box', 'ja': 'メッセージ入力欄の下のボタン'}),
    'message-buttons': (message_buttons, {'en': "Buttons of an assistant's card", 'ja': 'アシスタントのカードのボタン'}),
    'knowledge-base': (knowledge_base, {'en': 'Knowledge Base panel', 'ja': 'Knowledge Base のパネル'}),
    'live-conversation': (live_conversation, {'en': 'Live Conversation controls', 'ja': 'Live Conversation の操作欄'}),
    'side-column': (side_column, {'en': 'Tabs of the side column', 'ja': '右側の列のタブ'}),
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
                if draw is architecture:
                    arguments += (language,)
                f.write(draw(*arguments).svg())
            print(os.path.relpath(path, ROOT))


if __name__ == '__main__':
    main()
