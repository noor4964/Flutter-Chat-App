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
    final bool isWebLayout =
        PlatformHelper.isWeb && MediaQuery.of(context).size.width >= 1200;

    return Consumer<FeedProvider>(
      builder: (context, feed, _) {
        return Scaffold(
          appBar: isWebLayout
              ? null
              : AppBar(
                  title: const Text('News Feed'),
                  actions: [
                    // Subtle cache/offline status icon
                    if (feed.isFromCache && feed.posts.isNotEmpty)
                      Tooltip(
                        message: feed.lastServerSync != null
                            ? 'Showing cached data'
                            : 'Offline – showing cached data',
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            feed.lastServerSync != null
                                ? Icons.cloud_queue
                                : Icons.cloud_off,
                            size: 20,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    if (feed.isLoading && feed.posts.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _onRefresh,
                    ),
                  ],
                ),
          body: RefreshIndicator(
            onRefresh: _onRefresh,
            child: _buildBody(feed, theme, colorScheme, isWebLayout),
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
  ) {
    // First load — show skeleton shimmer
    if (feed.isLoading && feed.posts.isEmpty) {
      return _buildSkeletonList(theme);
    }

    // Error state with no cached data
    if (feed.error != null && feed.posts.isEmpty) {
      return _buildErrorState(feed, theme, colorScheme);
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
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
          child: _buildStoriesSection(feed, theme, colorScheme),
        ),

        // ── Create post card ────────────────────────────────────────
        const SliverToBoxAdapter(
          child: CreatePostCard(),
        ),

        // ── Section header ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Recent Posts',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // ── Offline / cached-data banner ───────────────────────────
        if (feed.isFromCache && feed.posts.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 16, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feed.lastServerSync != null
                          ? 'Showing cached posts – pull to refresh'
                          : 'You\'re offline – showing cached posts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (feed.lastServerSync != null)
                    Text(
                      _formatSyncAge(feed.lastServerSync!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer
                            .withOpacity(0.7),
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
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    Icons.post_add,
                    size: 80,
                    color: colorScheme.primary.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text('No posts yet', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Create a post or connect with friends',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
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
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'You\'re all caught up!',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
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
  ) {
    if (feed.isLoadingStories && feed.groupedStories.isEmpty) {
      return _buildStoriesShimmer(theme);
    }

    final storyEntries = feed.groupedStories.entries.toList();

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        // +1 for "Add Story" button at index 0
        itemCount: storyEntries.length + 1,
        itemBuilder: (context, index) {
          // Index 0: Add Story button
          if (index == 0) {
            return _buildAddStoryCircle(feed, theme, colorScheme);
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
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isOwn
                            ? [Colors.grey, Colors.grey.shade400]
                            : [Colors.purple, Colors.orange, Colors.pink],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: theme.scaffoldBackgroundColor,
                        backgroundImage:
                            firstStory.userProfileImage.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    firstStory.userProfileImage)
                                : null,
                        child:
                            firstStory.userProfileImage.isNotEmpty
                                ? null
                                : const Icon(Icons.person, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 68,
                    child: Text(
                      isOwn ? 'Your Story' : firstStory.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddStoryCircle(
    FeedProvider feed,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest,
            ),
            child: feed.hasActiveStory
                ? CircleAvatar(
                    radius: 30,
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
                : Icon(Icons.add, size: 30, color: colorScheme.primary),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 68,
            child: Text(
              feed.hasActiveStory ? 'Your Story' : 'Add Story',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  // ── Skeleton / Shimmer placeholders ───────────────────────────────────
  Widget _buildSkeletonList(ThemeData theme) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (context, index) {
        if (index == 0) return _buildStoriesShimmer(theme);
        return _buildPostSkeleton(theme);
      },
    );
  }

  Widget _buildStoriesShimmer(ThemeData theme) {
    final shimmerColor =
        theme.brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[300]!;

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 33, backgroundColor: shimmerColor),
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

  Widget _buildPostSkeleton(ThemeData theme) {
    final shimmerColor =
        theme.brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[300]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name row
            Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: shimmerColor),
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
            const SizedBox(height: 16),
            // Caption placeholder
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 200,
              height: 12,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            // Image placeholder
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: shimmerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────
  Widget _buildErrorState(
    FeedProvider feed,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              feed.error ?? 'Unable to load your feed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
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
