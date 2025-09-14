import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// A helper class to handle network image errors gracefully, especially for Cloudinary images
class SafeNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final Widget? errorWidget;
  final Widget? loadingWidget;
  final double? width;
  final double? height;
  final BoxFit fit;

  const SafeNetworkImage({
    Key? key,
    required this.imageUrl,
    this.errorWidget,
    this.loadingWidget,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return errorWidget ?? _defaultErrorWidget();
    }

    return Image.network(
      imageUrl!,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return loadingWidget ?? _defaultLoadingWidget();
      },
      errorBuilder: (context, error, stackTrace) {
        print('Image loading error for URL: $imageUrl - Error: $error');
        return errorWidget ?? _defaultErrorWidget();
      },
    );
  }

  Widget _defaultErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Colors.grey[600],
        size: 24,
      ),
    );
  }

  Widget _defaultLoadingWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}