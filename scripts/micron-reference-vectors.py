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
    if raw == "default" or rendered_color(raw) == "default":
        return ".default"
    if re.fullmatch(r"[0-9a-fA-F]{3}", raw):
        r, g, b = (int(c, 16) for c in raw)
        return f".rgb3(r: {r}, g: {g}, b: {b})"
    if re.fullmatch(r"[0-9a-fA-F]{6}", raw):
        r, g, b = (int(raw[i:i + 2], 16) for i in (0, 2, 4))
        return f".rgb6(r: {r}, g: {g}, b: {b})"
    if re.fullmatch(r"g[0-9]{2}", raw):
        return f".grey(percent: {int(raw[1:])})"
    raise ValueError(f"no Swift color for {raw!r}")


class Context:
    def __init__(self, fg, bg):
        self.fg = fg
        self.bg = bg

    def style(self, name, heading=None):
        fg, bg, bold, underline, italic = name
        theme_fg, theme_bg = DEFAULT_FG, "default"
        if heading is not None:
            theme = MP.STYLES_DARK["heading" + str(heading)]
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
                                 width, False, style))
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
            _, field_type, name, value, label, width, prechecked, style = segment
            spans.append(f".field(MicronField(fieldType: {field_type}, name: {swift_string(name)}, "
                         f"value: {swift_string(value)}, label: {swift_string(label)}, "
                         f"width: {width}, prechecked: {'true' if prechecked else 'false'}, "
                         f"style: {context.style(style)}))")
    return "[" + ", ".join(spans) + "]"


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
            fields = widget.partial_fields
            if "" in fields:
                raise ValueError("an empty partial field has no Swift representation")
            refresh = "nil" if widget.partial_refresh is None else repr(widget.partial_refresh)
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
