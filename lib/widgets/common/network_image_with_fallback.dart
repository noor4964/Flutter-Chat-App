import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NetworkImageWithFallback extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  final bool useCache;

  const NetworkImageWithFallback({
    Key? key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.useCache = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // If imageUrl is null or empty, return error widget directly
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildErrorContainer();
    }

    // Use a wrapper to handle border radius if specified
    Widget image;
    
    if (useCache) {
      // Use CachedNetworkImage which handles caching automatically
      image = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildErrorContainer(),
        cacheManager: DefaultCacheManager(),
      );
    } else {
      // Use regular Image.network with error handling
      image = Image.network(
        imageUrl!,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorContainer();
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return image;
  }

  Widget _buildPlaceholder() {
    return placeholder ?? 
      Container(
        width: width,
        height: height,
        color: Colors.grey[300],
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
  }

  Widget _buildErrorContainer() {
    return errorWidget ??
      Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.grey[600],
            size: 24,
          ),
        ),
      );
  }
}