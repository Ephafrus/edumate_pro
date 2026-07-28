import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// A lightweight rich-message editor: an HTML source field with a formatting
/// toolbar (wraps the current selection in tags) and a live preview toggle.
/// Used for broadcast messages, which are rendered in-app and emailed as
/// HTML.
class HtmlEditorField extends StatefulWidget {
  const HtmlEditorField({
    super.key,
    required this.controller,
    this.minLines = 8,
  });

  final TextEditingController controller;
  final int minLines;

  @override
  State<HtmlEditorField> createState() => _HtmlEditorFieldState();
}

class _HtmlEditorFieldState extends State<HtmlEditorField> {
  bool _preview = false;

  /// Wraps the selection (or inserts at the caret) with [open]…[close].
  void _wrap(String open, String close) {
    final c = widget.controller;
    final sel = c.selection;
    final text = c.text;
    if (!sel.isValid) {
      c.text = '$text$open$close';
      c.selection =
          TextSelection.collapsed(offset: c.text.length - close.length);
      return;
    }
    final selected = sel.textInside(text);
    final replaced = '$open$selected$close';
    c.text = sel.textBefore(text) + replaced + sel.textAfter(text);
    c.selection = TextSelection.collapsed(
        offset: sel.start + replaced.length - (selected.isEmpty ? close.length : 0));
    setState(() {});
  }

  void _insertBlock(String block) {
    final c = widget.controller;
    c.text = '${c.text}\n$block';
    c.selection = TextSelection.collapsed(offset: c.text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Bold',
              icon: const Icon(Icons.format_bold, size: 20),
              onPressed:
                  _preview ? null : () => _wrap('<b>', '</b>'),
            ),
            IconButton(
              tooltip: 'Italic',
              icon: const Icon(Icons.format_italic, size: 20),
              onPressed:
                  _preview ? null : () => _wrap('<i>', '</i>'),
            ),
            IconButton(
              tooltip: 'Underline',
              icon: const Icon(Icons.format_underline, size: 20),
              onPressed:
                  _preview ? null : () => _wrap('<u>', '</u>'),
            ),
            IconButton(
              tooltip: 'Heading',
              icon: const Icon(Icons.title, size: 20),
              onPressed:
                  _preview ? null : () => _wrap('<h2>', '</h2>'),
            ),
            IconButton(
              tooltip: 'Paragraph',
              icon: const Icon(Icons.notes, size: 20),
              onPressed:
                  _preview ? null : () => _wrap('<p>', '</p>'),
            ),
            IconButton(
              tooltip: 'Bullet list',
              icon: const Icon(Icons.format_list_bulleted, size: 20),
              onPressed: _preview
                  ? null
                  : () => _insertBlock(
                      '<ul>\n  <li>Item 1</li>\n  <li>Item 2</li>\n</ul>'),
            ),
            IconButton(
              tooltip: 'Link',
              icon: const Icon(Icons.link, size: 20),
              onPressed: _preview
                  ? null
                  : () => _wrap('<a href="https://">', '</a>'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit : Icons.visibility, size: 18),
              label: Text(_preview ? 'Edit' : 'Preview'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_preview)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 160),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Html(
                data: widget.controller.text.isEmpty
                    ? '<p style="color:grey">Nothing to preview yet…</p>'
                    : widget.controller.text),
          )
        else
          TextField(
            controller: widget.controller,
            minLines: widget.minLines,
            maxLines: widget.minLines + 12,
            decoration: const InputDecoration(
              hintText: '<p>Dear parents…</p>',
              helperText:
                  'HTML message — use the toolbar to format the selection',
            ),
          ),
      ],
    );
  }
}
