#!/usr/bin/env python3
"""Print the Micron parser vectors in MicronCodePointTests.swift, read from NomadNet.

Each vector runs through NomadNet's own `markup_to_attrmaps` (MicronParser.py:104-151),
directly or after `strip_modifiers` as the browser does (Browser.py:1846). The page colors
come from Browser.py:1824-1844, executed from the NomadNet source rather than copied.

`ensure_selected_styles` and `make_style` need a running app, so they are replaced: the
dark theme is selected, and a style is named by the state it was made from. The link branch
reads the app's color mode (MicronParser.py:1083), which a stub app provides.

The rows are printed as the `MicronNode` values `MicronParser.parsePage` returns, after the
normalization `MicronCodePointTests.observable` applies to the Swift side:

- A Python style carries no alignment (MicronParser.py:705-706), so a span's alignment isn't
  printed, and adjacent text runs with the same style are one run, as urwid joins them.
- A heading's theme colors (MicronParser.py:565-573) print as `.default`, because
  MicronParser.swift leaves heading theming to the renderer.
- A color `make_style` renders as "default" (MicronParser.py:803-845) prints as `.default`.

Run it with reticulum-interop's venv, with NomadNet 1.4.4 and LXMF 1.2.0 sources first on
the path:

    PYTHONPATH=nomadnet-1.4.4:lxmf-1.2.0 \\
        ../../reticulum-interop/.venv/bin/python scripts/micron-reference-vectors.py
"""
import inspect
import math
import os
import re
import sys
import textwrap
import types

import urwid

import nomadnet
from nomadnet.ui.textui import Browser
from nomadnet.ui.textui import MicronParser as MP
from nomadnet.util import strip_modifiers

PARSE_PAGE_VECTORS = [
    # Lines split on "\n" alone (MicronParser.py:117).
    "a\r\nb",
    "\r\n",
    "a\r\n\r\nb",
    "-\r\n",
    ">T\r\nx",
    "#c\r\nx",
    "`=\r\nx",
    # Line prefixes compare one code point (MicronParser.py:479-559).
    ">\u0301Title",
    ">>\u0301x",
    "#\u0301\nx",
    "\\\u0301`!x",
    ">H\n<\u0301x",
    "`t\u0301\n|a|b|\n|-|-|\n`t",
    "`tc\u0301\n|a|\n|1|\n`t",
    "`{\u0301p`5`a|b}",
    "`{p`5`a}\u0301",
    "`{p`5`\u0301a}",
    "`{p`5`a|\u0301b}",
    ">`<\u0301f`v>",
    ">\u0301`<f`v>",
    # Tag characters compare one code point (MicronParser.py:883-1132).
    "`!\u0301x",
    "`*\u0301x",
    "`_\u0301x",
    "`c\u0301x",
    "`l\u0301x",
    "`r\u0301x",
    "`a\u0301x",
    "`f\u0301x",
    "`b\u0301x",
    "`!a``\u0301x",
    "`\u0301x",
    "a\\\u0301`!b",
    "`Ff00\u0301x",
    "`F\u030100x",
    "`FTf00000\u0301x",
    "`Bf00\u0301x",
    "`:ab\u05b0c x",
    "`:a\u24b6b x",
    "`:\u0301a x",
    "`:a\u216bb x",
    "`[\u0301l`u]",
    "`[l`\u0301u]",
    "`[l`u]\u0301x",
    "`[l`u`a|\u0301b]",
    "`<\u0301n`v>",
    "`<n`\u0301v>",
    "`<n`v>\u0301x",
    "`<?|\u0301n|1`l>",
    "`<!\u0301|n`v>",
    "`<?\u0301|n|1`l>",
    "`<^\u0301|n|1`l>",
    # One grapheme, several code points.
    "`F\U0001f1fa\U0001f1f80x",
    "`B\u1100\u11610x",
    "`FT\U0001f1fa\U0001f1f80000x",
    "\u0d4e`!x",
    "`!\uff9ex",
    ">\uff9eT",
]

# Vectors for NN-01, one group per commit.
#
# Paste a group into PARSE_PAGE_VECTORS in scripts/micron-reference-vectors.py when you
# reach its commit. Each vector parses through markup_to_attrmaps with no browser step.
# Non-ASCII characters are \N{NAME} escapes, so this file stays ASCII; keep it that way.
#
# Each comment names the vector, the row of the original report ("chip N") when it has one,
# and "red" when the vector fails on NomadNetSwift 913c58b. The others pass there and pin
# behavior that must survive the fix.

# A color is read one code point at a time, as int(c, 16) and int(c) read it.
COLORS = [
    "`F\N{ARABIC-INDIC DIGIT ONE}\N{ARABIC-INDIC DIGIT TWO}\N{ARABIC-INDIC DIGIT THREE}x",  # arabic-indic color digits, chip 12, red
    "`FT+5aabbx",  # signed six-digit color, red
    "`Fg+5x",  # signed grey, red
    "`Fg\N{ARABIC-INDIC DIGIT FIVE}\N{ARABIC-INDIC DIGIT ZERO}x",  # arabic-indic grey, red
    "`FT\N{ARABIC-INDIC DIGIT FIVE}\N{ARABIC-INDIC DIGIT ZERO}\N{ARABIC-INDIC DIGIT FIVE}\N{ARABIC-INDIC DIGIT ZERO}\N{ARABIC-INDIC DIGIT FIVE}\N{ARABIC-INDIC DIGIT ZERO}x",  # arabic-indic six-digit color, red
    "`B\N{ARABIC-INDIC DIGIT ONE}\N{ARABIC-INDIC DIGIT TWO}\N{ARABIC-INDIC DIGIT THREE}x",  # arabic-indic background, red
    "`F+5ax",  # control: signed three-digit color, passes today
    "`Fg50x",  # control: grey, passes today
    "`FT5aabbcx",  # control: six-digit color, passes today
]

# A table needs two rows and a closing `t, and its width is int(line).
TABLES = [
    "`t\n|a|\n|1|",  # unclosed table at end of page, chip 9, red
    "`t\n|a|\n`t",  # one-row table, chip 10, red
    "`t\N{FULLWIDTH DIGIT FIVE}\N{FULLWIDTH DIGIT ZERO}\n|a|\n|1|\n`t",  # fullwidth table width, chip 11, red
    "`t 50\n|a|\n|1|\n`t",  # padded table width, red
    "`t5_0\n|a|\n|1|\n`t",  # underscore table width, red
    "`t\n`t",  # empty table, red
    "`tc50\n|a|\n|1|\n`t",  # control: aligned width, passes today
    "`t50\n|a|\n|1|\n`t",  # control: plain width, passes today
    "`t50\r\n|a|\r\n|1|\r\n`t",  # table width on a CRLF page, red
]

# A link's or partial's field list keeps its empty names.
FIELD_LISTS = [
    "`{p`5`a||b}",  # partial with an interior empty field, red
    "`{p`5`a|}",  # partial with a trailing empty field, red
    "`{p}",  # control: partial without fields, passes today
    "`[l`u`a||b]x",  # link with an interior empty field, red
    "`[l`u`a|]x",  # link with a trailing empty field, red
    "`[l`u`|]x",  # link with only a bar, red
    "`[l`u`]x",  # control: link with an empty field list, passes today
]

# A partial needs a float() refresh and at most three components.
PARTIALS = [
    "`{p`x}",  # partial with a failed float, chip 2, red
    "`{p`5`a`b}",  # partial with four components, chip 3, red
    "`{p``a}",  # empty refresh component, red
    "`{p`0x10}",  # hex refresh, red
    "`{p` 5 }",  # padded refresh, red
    "`{p`1_0}",  # underscore refresh, red
    "`{p`\N{ARABIC-INDIC DIGIT FIVE}}",  # arabic-indic refresh, red
    "`{p`0x1p3}",  # hex float refresh, red
    "`{p`nan(1)}",  # nan with payload, red
    "`{p`0.5}",  # control: fraction below one, passes today
    "`{p`-5}",  # control: negative, passes today
    "`{p`+5}",  # control: plus sign, passes today
    "`{p`5.}",  # control: trailing dot, passes today
    "`{p`1e1}",  # control: exponent, passes today
    "`{p`inf}",  # control: inf, passes today
    "`{p`nan}",  # control: nan, passes today
    "`{p`INFINITY}",  # control: INFINITY, passes today
]

# A link with four components or an empty URL is skipped whole.
LINKS = [
    "`[a`b`c`d]x",  # link with four components, chip 4, red
    "`[l`]x",  # link with an empty url, chip 5, red
]

# A text field's flags are width, then x, then rows, each read with int().
FIELDS = [
    "`<10x3|n`v>",  # field with a rows flag, chip 6, red
    "`<10x|n`v>",  # width with an empty rows flag, red
    "`< 10|n`v>",  # padded width, red
    "`<300|n`v>",  # control: width clamps to 256, passes today
    "`<x3|n`v>",  # rows without a width, red
    "`<10x999|n`v>",  # rows clamp to 256, red
    "`<10x0|n`v>",  # rows clamp to 1, red
    "`<10x-3|n`v>",  # negative rows, red
    "`<10xq|n`v>",  # invalid rows, red
    "`<qx3|n`v>",  # invalid width, valid rows, red
    "`<q|n`v>",  # control: invalid width, passes today
    "`<?10|n`v>",  # checkbox keeps the default width, red
    "`<^10x3|n`v>",  # radio keeps the default width, passes today
    "`<!10x3|n`v>",  # masked field takes width and rows, red
]

# A line with a field loses its leading > before the escape and comment checks.
LINE_PREFIXES = [
    ">#`<x`y>",  # comment prefix after the heading strip, chip 1, red
    ">>#x`<n`v>",  # comment after a heading strip, red
    ">\\`t`<n`v>",  # escape after a heading strip, red
    ">\\x`<n`v>",  # control: escape then letter, passes today
    ">-`<n`v>",  # control: rule prefix, passes today
    "><`<n`v>",  # control: reset prefix, passes today
]

# A heading is made in the heading theme's style, and the page's style comes back.
HEADINGS = [
    ">`!T\nx",  # heading restores bold, chip 7, red
    "`!a\n>T",  # heading ignores earlier bold, chip 8, red
    "`!\n>T\n`!x",  # heading ignores earlier bold, later toggle, red
    "`_a\n>T\nb",  # heading ignores earlier underline, red
    ">`*T\nx",  # heading restores italic, red
    "#!fg=f00\n#!bg=00f\n>T\nx",  # heading ignores the page colors, red
]

# A slug keeps ASCII letters and digits, and lowercases last.
SLUGS = [
    ">\N{KELVIN SIGN}",  # kelvin sign slug, chip 13, red
    ">a`}b",  # closing brace is not a micron code, red
    ">\N{LATIN CAPITAL LETTER I WITH DOT ABOVE}x",  # dotted capital I, red
]

ALL = COLORS + TABLES + FIELD_LISTS + PARTIALS + LINKS + FIELDS + LINE_PREFIXES + HEADINGS + SLUGS

if __name__ == "__main__":
    print(len(ALL), "vectors")

PARSE_PAGE_VECTORS += COLORS + TABLES + FIELD_LISTS + PARTIALS + LINKS + FIELDS + LINE_PREFIXES + HEADINGS + SLUGS

BROWSER_VECTORS = [
    "a\r\nb",
    "`F\U0001f1fa\U0001f1f80x",
    "`B\u1100\u11610x",
    "\u0d4e`!x",
    "`!\uff9ex",
    ">\uff9eT",
]

PAGE_COLOR_VECTORS = [
    "\u0d4e#!fg=f00\n",
    "#!fg=\u0301ab\n#!fg=0f0\n",
    "#!bg=\u0301ab\n#!bg=00f\n",
    "#!fg=f00\r\n",
    "#!fg=ab\r\n",
]


class StubApp:
    """The attributes of NomadNetworkApp that MicronParser reads."""

    class ui:
        colormode = 2**24
        glyphs = {}


nomadnet.NomadNetworkApp.get_shared_instance = staticmethod(lambda: StubApp)

DEFAULT_FG = MP.STYLES_DARK["plain"]["fg"]


def stub_ensure_selected_styles():
    MP.SELECTED_STYLES = MP.STYLES_DARK


class NamedSpec(urwid.AttrSpec):
    def __init__(self, name):
        super().__init__("default", "default", colors=2**24)
        self.micron_name = name


def stub_make_style(state):
    name = (
        state["fg_color"],
        state["bg_color"],
        state["formatting"]["bold"],
        state["formatting"]["underline"],
        state["formatting"]["italic"],
    )
    MP.SYNTH_SPECS.setdefault(name, [NamedSpec(name)] * 5)
    return name


class NamedLinkSpec(MP.LinkSpec):
    def __init__(self, link_target, orig_spec, cm=256):
        super().__init__(link_target, orig_spec, cm=cm)
        self.micron_name = orig_spec.micron_name


class TableMarker(urwid.Text):
    def __init__(self, lines, align, max_width):
        super().__init__("")
        self.table = (list(lines), align, max_width)


original_make_style = MP.make_style
original_render_table = MP.render_table
original_parse_line = MP.parse_line
original_slugify = MP.slugify_micron
last_slug = []


def recording_render_table(lines, state, url_delegate):
    rows = original_render_table(lines, state, url_delegate)
    if rows is None:
        return None
    return [TableMarker(lines, state["table_align"], state["table_maxwidth"])]


def recording_slugify(text):
    slug = original_slugify(text)
    last_slug.append(slug)
    return slug


def recording_parse_line(line, state, url_delegate):
    del last_slug[:]
    widgets = original_parse_line(line, state, url_delegate)
    for widget in widgets or []:
        widget.micron_align = state["align"]
        widget.micron_slug = last_slug[-1] if last_slug else ""
    return widgets


MP.ensure_selected_styles = stub_ensure_selected_styles
MP.make_style = stub_make_style
MP.LinkSpec = NamedLinkSpec
MP.render_table = recording_render_table
MP.parse_line = recording_parse_line
MP.slugify_micron = recording_slugify
stub_ensure_selected_styles()


def rendered_color(raw):
    """What make_style's high_color renders `raw` as (MicronParser.py:796-845)."""
    for const in original_make_style.__code__.co_consts:
        if isinstance(const, types.CodeType) and const.co_name == "high_color":
            return types.FunctionType(const, vars(MP))(raw)
    raise LookupError("make_style has no high_color")


def page_colors(markup):
    """Browser.py:1824-1844, run from the NomadNet 1.4.4 source."""
    source = inspect.getsource(Browser.Browser)
    start = source.index("            self.page_background_color = None\n            bgpos")
    end = source.index("            try: self.attr_maps = markup_to_attrmaps", start)
    snippet = textwrap.dedent(source[start:end])
    page = types.SimpleNamespace(markup=markup)
    exec(snippet, {}, {"self": page})
    return page.page_foreground_color, page.page_background_color


def swift_string(text):
    out = []
    for char in text:
        value = ord(char)
        if char == '"':
            out.append('\\"')
        elif char == "\\":
            out.append("\\\\")
        elif char == "\n":
            out.append("\\n")
        elif char == "\r":
            out.append("\\r")
        elif 0x20 <= value < 0x7F:
            out.append(char)
        else:
            out.append(f"\\u{{{value:X}}}")
    return '"' + "".join(out) + '"'


def swift_color(raw, theme_default, page_default):
    if raw == page_default and page_default is not None:
        pass
    elif raw == theme_default:
        return ".default"
    rendered = rendered_color(raw)
    if raw == "default" or rendered == "default":
        return ".default"
    if rendered.startswith("g"):
        return f".grey(percent: {int(rendered[1:])})"
    if len(raw) == 3:
        r, g, b = (int(rendered[i], 16) for i in (1, 3, 5))
        return f".rgb3(r: {r}, g: {g}, b: {b})"
    if len(raw) == 6:
        r, g, b = (int(rendered[i:i + 2], 16) for i in (1, 3, 5))
        return f".rgb6(r: {r}, g: {g}, b: {b})"
    raise ValueError(f"no Swift color for {raw!r}")


class Context:
    def __init__(self, fg, bg):
        self.fg = fg
        self.bg = bg

    def style(self, name, heading=None):
        fg, bg, bold, underline, italic = name
        theme_fg, theme_bg = DEFAULT_FG, "default"
        if heading is not None:
            theme = MP.STYLES_DARK["heading" + str(min(heading, 3))]
            theme_fg, theme_bg = theme["fg"], theme["bg"]
        args = []
        if bold:
            args.append("bold: true")
        if underline:
            args.append("underline: true")
        if italic:
            args.append("italic: true")
        fg_color = swift_color(fg, theme_fg, self.fg)
        bg_color = swift_color(bg, theme_bg, self.bg)
        if fg_color != ".default":
            args.append(f"fgColor: {fg_color}")
        if bg_color != ".default":
            args.append(f"bgColor: {bg_color}")
        return ".init(" + ", ".join(args) + ")"


def text_segments(widget):
    text, runs = widget.get_text()
    segments = []
    position = 0
    for attr, length in runs:
        run = text[position:position + length]
        position += length
        if attr is None:
            if run.strip(" "):
                raise ValueError(f"unstyled run {run!r}")
            continue
        if isinstance(attr, MP.LinkSpec):
            segments.append(("link", run, attr.link_target, attr.link_fields or [],
                             attr.micron_name))
        else:
            segments.append(("text", run, attr))
    if position != len(text):
        segments.append(("text", text[position:], None))
    return segments


def column_segments(columns):
    segments = []
    for widget, (kind, width, _) in columns.contents:
        if isinstance(widget, urwid.AttrMap):
            style = widget.attr_map[None]
            field = widget.original_widget
            if isinstance(field, urwid.RadioButton):
                segments.append(("field", ".radio", field.field_name, field.field_value,
                                 field.label, 24, field.state, style))
            elif isinstance(field, urwid.CheckBox):
                segments.append(("field", ".checkbox", field.field_name, field.field_value,
                                 field.label, 24, field.state, style))
            else:
                field_type = ".masked" if field._mask else ".text"
                segments.append(("field", field_type, field.field_name, field.edit_text, "",
                                 width, False, style, field._min_rows))
        else:
            segments.extend(text_segments(widget))
    return segments


def merged(segments):
    out = []
    for segment in segments:
        if out and segment[0] == "text" and out[-1][0] == "text" and out[-1][2] == segment[2]:
            out[-1] = ("text", out[-1][1] + segment[1], segment[2])
        else:
            out.append(segment)
    return out


def swift_spans(segments, context, heading=None):
    spans = []
    for segment in merged(segments):
        if segment[0] == "text":
            spans.append(f".text({swift_string(segment[1])}, "
                         f"style: {context.style(segment[2], heading)})")
        elif segment[0] == "link":
            _, label, url, fields, style = segment
            field_list = "[" + ", ".join(swift_string(f) for f in fields) + "]"
            spans.append(f".link(MicronLink(label: {swift_string(label)}, "
                         f"url: {swift_string(url)}, fields: {field_list}, "
                         f"style: {context.style(style)}))")
        else:
            field_type, name, value, label, width, prechecked, style = segment[1:8]
            rows = segment[8] if len(segment) > 8 else 1
            rows_arg = f"rows: {rows}, " if rows != 1 else ""
            spans.append(f".field(MicronField(fieldType: {field_type}, name: {swift_string(name)}, "
                         f"value: {swift_string(value)}, label: {swift_string(label)}, "
                         f"width: {width}, {rows_arg}prechecked: {'true' if prechecked else 'false'}, "
                         f"style: {context.style(style)}))")
    return "[" + ", ".join(spans) + "]"


def swift_double(value):
    if math.isinf(value):
        return ".infinity"
    if math.isnan(value):
        return ".nan"
    return repr(value)


def swift_alignment(align):
    return {"left": ".left", "center": ".center", "right": ".right", None: "nil",
            "l": ".left", "c": ".center", "r": ".right"}[align]


def swift_rows(attrmaps, context):
    rows = []
    headers = set(attrmaps.header_rows)
    for index, attrmap in enumerate(attrmaps):
        widget = attrmap.original_widget
        align = getattr(widget, "micron_align", None)
        slug = getattr(widget, "micron_slug", "")
        while isinstance(widget, (urwid.AttrMap, urwid.Padding)):
            widget = widget.original_widget
        depth = attrmaps.row_levels[index]
        if isinstance(widget, TableMarker):
            lines, table_align, max_width = widget.table
            row_list = "[" + ", ".join(f"[{swift_string(line)}]" for line in lines) + "]"
            width = "nil" if max_width is None else str(max_width)
            rows.append(f".table(rows: {row_list}, alignment: {swift_alignment(table_align)}, "
                        f"maxWidth: {width})")
        elif isinstance(widget, urwid.Divider):
            rows.append(f".horizontalRule(character: {swift_string(widget.div_char)})")
        elif isinstance(widget, urwid.Pile) and hasattr(widget, "partial_url"):
            fields = [] if widget.partial_fields == [""] else widget.partial_fields
            refresh = "nil" if widget.partial_refresh is None else swift_double(widget.partial_refresh)
            field_list = "[" + ", ".join(swift_string(f) for f in fields) + "]"
            rows.append(f".partial(MicronPartial(url: {swift_string(widget.partial_url)}, "
                        f"refreshInterval: {refresh}, fields: {field_list}))")
        elif index in headers:
            level = attrmaps.header_levels[index]
            spans = swift_spans(text_segments(widget), context, heading=level)
            rows.append(f".heading(level: {level}, spans: {spans}, depth: {level}, "
                        f"slug: {swift_string(slug)})")
        elif isinstance(widget, MP.FormColumns):
            spans = swift_spans(column_segments(widget), context)
            rows.append(f".line({spans}, depth: {depth}, alignment: {swift_alignment(align)})")
        elif align is None and widget.get_text()[0] == "":
            rows.append(".emptyLine")
        else:
            spans = swift_spans(text_segments(widget), context)
            rows.append(f".line({spans}, depth: {depth}, alignment: {swift_alignment(align)})")
    return rows


def swift_anchors(anchors):
    if not anchors:
        return "[:]"
    return "[" + ", ".join(f"{swift_string(k)}: {v}" for k, v in anchors.items()) + "]"


def parse(markup, through_browser):
    fg, bg = page_colors(markup)
    source = strip_modifiers(markup) if through_browser else markup
    delegate = types.SimpleNamespace()
    attrmaps = MP.markup_to_attrmaps(source, url_delegate=delegate, fg_color=fg, bg_color=bg)
    return attrmaps, Context(fg, bg)


def print_vectors(name, vectors, through_browser):
    print(f"  static let {name}: [Vector] = [")
    for markup in vectors:
        attrmaps, context = parse(markup, through_browser)
        rows = swift_rows(attrmaps, context)
        print(f"    Vector(")
        print(f"      {swift_string(markup)},")
        if rows:
            print("      [")
            for row in rows:
                print(f"        {row},")
            print("      ],")
        else:
            print("      [],")
        print(f"      anchors: {swift_anchors(attrmaps.anchors)}),")
    print("  ]")


def print_page_colors():
    print("  static let pageColorVectors: [PageColorVector] = [")
    for markup in PAGE_COLOR_VECTORS:
        fg, bg = page_colors(markup)
        colors = []
        for raw in (fg, bg):
            if raw is None or rendered_color(raw) == "default":
                colors.append("nil")
            else:
                colors.append(swift_color(raw, None, None))
        print(f"    PageColorVector({swift_string(markup)}, "
              f"foreground: {colors[0]}, background: {colors[1]}),")
    print("  ]")


def main():
    print(f"// NomadNet {nomadnet.__file__}, urwid {urwid.__version__}, Python {sys.version.split()[0]}")
    print_vectors("parsePageVectors", PARSE_PAGE_VECTORS, through_browser=False)
    print_vectors("browserVectors", BROWSER_VECTORS, through_browser=True)
    print_page_colors()


if __name__ == "__main__":
    main()
