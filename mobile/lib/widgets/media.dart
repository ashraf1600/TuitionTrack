import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/session.dart';
import 'theme.dart';
import 'ui.dart';

bool isPdf(String url) => RegExp(r'\.pdf(\?|$)', caseSensitive: false).hasMatch(url);

/// Only files uploaded to this app, or served over http(s), are ever shown.
bool isSafeMedia(String url) => url.startsWith('/media/') || url.startsWith('http://') || url.startsWith('https://');

Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(context.read<Session>().api.mediaUrl(url));
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) showToast(context, 'Could not open the file.', error: true);
  }
}

/// A picture stored on the server. Tap to see it full screen and zoom.
class ServerImage extends StatelessWidget {
  const ServerImage(this.url, {super.key, this.height = 200, this.fit = BoxFit.contain, this.label = 'Picture'});
  final String url;
  final double height;
  final BoxFit fit;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty || !isSafeMedia(url)) return const SizedBox.shrink();
    final full = context.read<Session>().api.mediaUrl(url);
    if (isPdf(url)) {
      return OutlinedButton.icon(
        onPressed: () => openExternal(context, url),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text('Open $label (PDF)'),
      );
    }
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, title: Text(label)),
              body: InteractiveViewer(maxScale: 6, child: Center(child: Image.network(full))),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: Colors.white,
            constraints: BoxConstraints(maxHeight: height),
            child: Image.network(
              full,
              fit: fit,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : SizedBox(height: height / 2, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
              errorBuilder: (context, error, stack) => Container(
                height: 80,
                color: AppColors.card,
                alignment: Alignment.center,
                child: const Text('Picture could not be loaded', style: TextStyle(color: AppColors.muted)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user take a photo or choose pictures, uploads them and returns their stored addresses.
/// Returns an empty list when the user cancels.
Future<List<String>> pickAndUpload(BuildContext context, {bool multiple = true}) async {
  final api = context.read<Session>().api;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(multiple ? 'Choose pictures' : 'Choose a picture'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return [];

  final picker = ImagePicker();
  List<XFile> files;
  try {
    // Resizing keeps phone photos well under the 10 MB upload limit while staying readable.
    if (source == ImageSource.gallery && multiple) {
      files = await picker.pickMultiImage(maxWidth: 2200, maxHeight: 2200, imageQuality: 85);
    } else {
      final one = await picker.pickImage(source: source, maxWidth: 2200, maxHeight: 2200, imageQuality: 85);
      files = one == null ? [] : [one];
    }
  } catch (_) {
    if (context.mounted) showToast(context, 'Could not open the camera or gallery. Check the app permissions.', error: true);
    return [];
  }

  final urls = <String>[];
  for (final file in files) {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) throw ApiException('"${file.name}" is larger than 10 MB.');
      var name = file.name.toLowerCase();
      if (!RegExp(r'\.(png|jpe?g|webp)$').hasMatch(name)) name = '$name.jpg';
      urls.add(await api.upload(bytes, name));
    } on ApiException catch (error) {
      if (context.mounted) showToast(context, error.message, error: true);
    }
  }
  return urls;
}
