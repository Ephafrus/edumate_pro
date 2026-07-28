import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// A picked file's bytes + metadata, ready for [StorageService] uploads.
class PickedUpload {
  const PickedUpload(this.filename, this.bytes, this.contentType);
  final String filename;
  final Uint8List bytes;
  final String? contentType;
}

/// Opens the platform file picker (images/PDF) and returns the file bytes —
/// the same code path on web, Android and iOS.
Future<PickedUpload?> pickDocument() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    withData: true,
  );
  final file = result?.files.single;
  if (file == null || file.bytes == null) return null;
  final ext = (file.extension ?? '').toLowerCase();
  final contentType = switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => null,
  };
  return PickedUpload(file.name, file.bytes!, contentType);
}

/// Outlined button that picks a document and reports it upward; shows the
/// picked/uploaded filename beneath.
class UploadButton extends StatelessWidget {
  const UploadButton({
    super.key,
    required this.label,
    required this.onPicked,
    this.filename,
    this.busy = false,
  });

  final String label;
  final ValueChanged<PickedUpload> onPicked;
  final String? filename;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final picked = await pickDocument();
                  if (picked != null) onPicked(picked);
                },
          icon: busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(label),
        ),
        if (filename != null && filename!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(filename!,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
