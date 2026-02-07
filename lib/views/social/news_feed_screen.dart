import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter_chat_app/providers/feed_provider.dart';
import 'package:flutter_chat_app/widgets/post_card.dart';
import 'package:flutter_chat_app/widgets/create_post_card.dart';
import 'package:flutter_chat_app/services/platform_helper.dart';
import 'package:flutter_chat_app/views/story_view_screen.dart';

/// News Feed screen backed by [FeedProvider].
///
/// Survives tab switches because [MessengerHomeScreen] keeps it inside an
/// [IndexedStack] (which never removes children from the tree).
/// Scroll-based pagination triggers [FeedProvider.loadMore] near the bottom.
class NewsFeedScreen extends StatefulWidget {
  const NewsFeedScreen({Key? key}) : super(key: key);

  @override
  State<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends State<NewsFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  // ── Lifecycle ─────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Restore scroll position from FeedProvider cache (safety net for
    // edge cases where the widget is rebuilt, e.g. web layout changes).
    final feed = context.read<FeedProvider>();
    if (feed.savedScrollOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final maxExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(
            feed.savedScrollOffset.clamp(0.0, maxExtent),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    // Persist scroll offset into FeedProvider so it survives widget disposal
    if (_scrollController.hasClients) {
      context.read<FeedProvider>().savedScrollOffset =
          _scrollController.offset;
    }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Infinite-scroll trigger ───────────────────────────────────────────
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      context.read<FeedProvider>().loadMore();
    }
  }

  // ── Pull-to-refresh ───────────────────────────────────────────────────
  Future<void> _onRefresh() async {
    await context.read<FeedProvider>().refresh();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Returns a human-friendly age string like "2 min ago" for the sync badge.
  String _formatSyncAge(DateTime syncTime) {
    final diff = DateTime.now().difference(syncTime);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bool isWebLayout =
        PlatformHelper.isWeb && MediaQuery.of(context).size.width >= 1200;

    return Consumer<FeedProvider>(
      builder: (context, feed, _) {
        return Scaffold(
          backgroundColor: isDark ? Colors.black : Colors.white,
          body: RefreshIndicator(
            onRefresh: _onRefresh,
            child: _buildBody(feed, theme, colorScheme, isWebLayout, isDark),
          ),
        );
      },
    );
  }

  // ── Body builder ──────────────────────────────────────────────────────
  Widget _buildBody(
    FeedProvider feed,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isWebLayout,
    bool isDark,
  ) {
    // First load — show skeleton shimmer
    if (feed.isLoading && feed.posts.isEmpty) {
      return _buildSkeletonList(theme, isDark);
    }

    // Error state with no cached data
    if (feed.error != null && feed.posts.isEmpty) {
      return _buildErrorState(feed, theme, colorScheme, isDark);
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Collapsible header (replaces AppBar) ─────────────────
        if (!isWebLayout)
          SliverAppBar(
            floating: true,
            snap: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor:
                isDark ? Colors.black : Colors.white,
            toolbarHeight: 56,
            title: Text(
              'Chatify',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                foreground: Paint()
                  ..shader = LinearGradient(
                    colors: [
                      colorScheme.primary,
                      HSLColor.fromColor(colorScheme.primary)
                          .withHue(
                              (HSLColor.fromColor(colorScheme.primary).hue +
                                      30) %
                                  360)
                          .toColor(),
                    ],
                  ).createShader(const Rect.fromLTWH(0, 0, 150, 30)),
              ),
            ),
            centerTitle: false,
            actions: [
              // Subtle cache indicator
              if (feed.isFromCache && feed.posts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    feed.lastServerSync != null
                        ? Icons.cloud_queue
                        : Icons.cloud_off,
                    size: 20,
                    color: isDark ? Colors.white38 : Colors.grey[400],
                  ),
                ),
              // Loading spinner
              if (feed.isLoading && feed.posts.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              // Refresh icon
              IconButton(
                icon: Icon(
                  Icons.favorite_border,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: _onRefresh,
                splashRadius: 22,
              ),
            ],
          ),

        // ── Web header ──────────────────────────────────────────────
        if (isWebLayout)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Posts',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (feed.isFromCache && feed.posts.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Tooltip(
                          message: feed.lastServerSync != null
                              ? 'Cached \u2013 ${_formatSyncAge(feed.lastServerSync!)}'
                              : 'Offline \u2013 cached data',
                          child: Icon(
                            Icons.cloud_off,
                            size: 18,
                            color: colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _onRefresh,
                    tooltip: 'Refresh Feed',
                  ),
                ],
              ),
            ),
          ),

        // ── Stories row ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _buildStoriesSection(feed, theme, colorScheme, isDark),
        ),

        // ── Create post card ────────────────────────────────────────
        const SliverToBoxAdapter(
          child: CreatePostCard(),
        ),

        // ── Offline / cached-data banner ───────────────────────────
        if (feed.isFromCache && feed.posts.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 16,
                      color: isDark ? Colors.white54 : Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feed.lastServerSync != null
                          ? 'Showing cached posts \u2013 pull to refresh'
                          : 'You\'re offline \u2013 showing cached posts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white54 : Colors.grey[600],
                      ),
                    ),
                  ),
                  if (feed.lastServerSync != null)
                    Text(
                      _formatSyncAge(feed.lastServerSync!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark ? Colors.white38 : Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),
          ),

        // ── Error banner (with cached data still showing) ───────────
        if (feed.error != null && feed.posts.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 18, color: colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feed.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _onRefresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),

        // ── Posts list (or empty state) ─────────────────────────────
        if (feed.posts.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 72,
                    color: isDark ? Colors.white24 : Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text('No posts yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    'Create a post or connect with friends',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white54 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index < feed.posts.length) {
                  return PostCard(post: feed.posts[index]);
                }
                // Last item: loading-more indicator
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              },
              childCount: feed.posts.length +
                  (feed.isLoadingMore && feed.hasMorePosts ? 1 : 0),
            ),
          ),

        // ── End-of-feed indicator ───────────────────────────────────
        if (!feed.hasMorePosts && feed.posts.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: isDark ? Colors.white24 : Colors.grey[300],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'re all caught up!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.white38 : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Stories section ───────────────────────────────────────────────────
  Widget _buildStoriesSection(
    FeedProvider feed,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    if (feed.isLoadingStories && feed.groupedStories.isEmpty) {
      return _buildStoriesShimmer(theme, isDark);
    }

    final storyEntries = feed.groupedStories.entries.toList();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.06),
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        height: 116,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          // +1 for "Add Story" button at index 0
          itemCount: storyEntries.length + 1,
          itemBuilder: (context, index) {
            // Index 0: Add Story button
            if (index == 0) {
              return _buildAddStoryCircle(
                  feed, theme, colorScheme, isDark);
            }

            final entry = storyEntries[index - 1];
            final userId = entry.key;
            final stories = entry.value;
            if (stories.isEmpty) return const SizedBox.shrink();

            final firstStory = stories.first;
            final isOwn = userId == feed.currentUserId;

            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StoryViewScreen(
                      stories: stories,
                      userId: userId,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isOwn
                              ? [
                                  Colors.grey.shade400,
                                  Colors.grey.shade300
                                ]
                              : [
                                  colorScheme.primary,
                                  HSLColor.fromColor(colorScheme.primary)
                                      .withHue((HSLColor.fromColor(
                                                      colorScheme.primary)
                                                  .hue +
                                              40) %
                                          360)
                                      .toColor(),
                                  Colors.pinkAccent,
                                ],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: CircleAvatar(
                          radius: 33,
                          backgroundColor: isDark
                              ? const Color(0xFF1A1C1E)
                              : Colors.white,
                          backgroundImage:
                              firstStory.userProfileImage.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      firstStory.userProfileImage)
                                  : null,
                          child: firstStory.userProfileImage.isNotEmpty
                              ? null
                              : const Icon(Icons.person, size: 28),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 72,
                      child: Text(
                        isOwn ? 'Your Story' : firstStory.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAddStoryCircle(
    FeedProvider feed,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF121212) : const Color(0xFFF0F0F3),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.black.withOpacity(0.06),
                width: 1,
              ),
            ),
            child: feed.hasActiveStory
                ? CircleAvatar(
                    radius: 35,
                    backgroundImage:
                        (feed.currentUserProfileImageUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImageProvider(
                                feed.currentUserProfileImageUrl!)
                            : null,
                    child:
                        (feed.currentUserProfileImageUrl?.isNotEmpty ?? false)
                            ? null
                            : const Icon(Icons.person, size: 28),
                  )
                : Icon(Icons.add,
                    size: 30, color: colorScheme.primary),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 72,
            child: Text(
              feed.hasActiveStory ? 'Your Story' : 'Add Story',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Skeleton / Shimmer placeholders ───────────────────────────────────
  Widget _buildSkeletonList(ThemeData theme, bool isDark) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (context, index) {
        if (index == 0) return _buildStoriesShimmer(theme, isDark);
        return _buildPostSkeleton(theme, isDark);
      },
    );
  }

  Widget _buildStoriesShimmer(ThemeData theme, bool isDark) {
    final shimmerColor =
        isDark ? const Color(0xFF121212) : const Color(0xFFE8E8EA);

    return SizedBox(
      height: 116,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 36, backgroundColor: shimmerColor),
              const SizedBox(height: 6),
              Container(
                width: 48,
                height: 10,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostSkeleton(ThemeData theme, bool isDark) {
    final shimmerColor =
        isDark ? const Color(0xFF121212) : const Color(0xFFE8E8EA);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header skeleton
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(radius: 18, backgroundColor: shimmerColor),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Image skeleton — full width, no border radius
        Container(
          width: double.infinity,
          height: 300,
          color: shimmerColor,
        ),
        // Action bar skeleton
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        // Divider
        Divider(
          height: 1,
          thickness: 0.5,
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.black.withOpacity(0.08),
        ),
      ],
    );
  }

  // ── Error state ───────────────────────────────────────────────────────
  Widget _buildErrorState(
    FeedProvider feed,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 64,
                color: isDark ? Colors.white24 : Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              feed.error ?? 'Unable to load your feed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
