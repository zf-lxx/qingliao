import 'package:flutter/material.dart';

import '../ui/theme/tg_tokens.dart';

/// Link preview inside a bubble: left accent bar, site, title, description,
/// optional remote image. Independent layout, not Telegram source.
class LinkPreviewCard extends StatelessWidget {
  final Map<String, dynamic> preview;
  final VoidCallback? onTap;
  const LinkPreviewCard({super.key, required this.preview, this.onTap});

  String get _site {
    final name = preview['site_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final raw = preview['url']?.toString() ?? '';
    return Uri.tryParse(raw)?.host ?? '';
  }

  String get _title => preview['title']?.toString() ?? '';
  String get _description => preview['description']?.toString() ?? '';
  String get _image => preview['image']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return GestureDetector(
      key: const Key('link-preview'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: TgTokens.accent, width: 2)),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_site.isNotEmpty)
              Text(
                _site,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: TgTokens.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (_title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  _title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Color(0xffeef4fa),
                  ),
                ),
              ),
            if (_description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: TgTokens.muted,
                  ),
                ),
              ),
            if (image.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0x33223344),
                        child: Center(
                          child: Icon(
                            Icons.link,
                            color: TgTokens.muted,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
