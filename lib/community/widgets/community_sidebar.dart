import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:lemmy_api_client/v3.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swipeable_page_route/swipeable_page_route.dart';

import 'package:thunder/account/bloc/account_bloc.dart';
import 'package:thunder/community/bloc/community_bloc.dart';
import 'package:thunder/core/auth/bloc/auth_bloc.dart';
import 'package:thunder/core/enums/local_settings.dart';
import 'package:thunder/core/singletons/preferences.dart';
import 'package:thunder/shared/snackbar.dart';
import 'package:thunder/shared/user_avatar.dart';
import 'package:thunder/utils/instance.dart';
import 'package:thunder/utils/navigate_user.dart';
import 'package:thunder/utils/swipe.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/common_markdown_body.dart';
import '../../thunder/bloc/thunder_bloc.dart';
import '../../user/pages/user_page.dart';
import '../../utils/date_time.dart';
import '../pages/create_post_page.dart';

class CommunitySidebar extends StatefulWidget {
  final FullCommunityView? communityInfo;
  final SubscribedType? subscribedType;
  final BlockedCommunity? blockedCommunity;

  const CommunitySidebar({
    super.key,
    required this.communityInfo,
    required this.subscribedType,
    required this.blockedCommunity,
  });

  @override
  State<CommunitySidebar> createState() => _CommunitySidebarState();
}

class _CommunitySidebarState extends State<CommunitySidebar> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  bool isBlocked = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isUserLoggedIn = context.read<AuthBloc>().state.isLoggedIn;

    if (widget.blockedCommunity != null) {
      isBlocked = widget.blockedCommunity!.blocked;
    } else {
      isBlocked = widget.communityInfo!.communityView.blocked;
    }

    return Container(
      alignment: Alignment.topRight,
      child: FractionallySizedBox(
        widthFactor: 0.8,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(Colors.black.withOpacity(0.25), theme.colorScheme.background),
                          theme.colorScheme.background,
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: theme.colorScheme.background,
                    ),
                  ),
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        end: Alignment.topCenter,
                        begin: Alignment.bottomCenter,
                        colors: [
                          Color.alphaBlend(Colors.black.withOpacity(0.25), theme.colorScheme.background),
                          theme.colorScheme.background,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 100),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return SizeTransition(
                        sizeFactor: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: isBlocked == false
                        ? Padding(
                            padding: const EdgeInsets.only(
                              top: 10,
                              left: 12,
                              right: 12,
                              bottom: 4,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: isUserLoggedIn
                                        ? () async {
                                            HapticFeedback.mediumImpact();
                                            CommunityBloc communityBloc = context.read<CommunityBloc>();
                                            AccountBloc accountBloc = context.read<AccountBloc>();
                                            ThunderBloc thunderBloc = context.read<ThunderBloc>();

                                            final ThunderState state = context.read<ThunderBloc>().state;
                                            final bool reduceAnimations = state.reduceAnimations;

                                            SharedPreferences prefs = (await UserPreferences.instance).sharedPreferences;
                                            DraftPost? newDraftPost;
                                            DraftPost? previousDraftPost;
                                            String draftId = '${LocalSettings.draftsCache.name}-${widget.communityInfo!.communityView.community.id}';
                                            String? draftPostJson = prefs.getString(draftId);
                                            if (draftPostJson != null) {
                                              previousDraftPost = DraftPost.fromJson(jsonDecode(draftPostJson));
                                            }
                                            Timer timer = Timer.periodic(const Duration(seconds: 10), (Timer t) {
                                              if (newDraftPost?.isNotEmpty == true) {
                                                prefs.setString(draftId, jsonEncode(newDraftPost!.toJson()));
                                              }
                                            });

                                            Navigator.of(context)
                                                .push(
                                              SwipeablePageRoute(
                                                transitionDuration: reduceAnimations ? const Duration(milliseconds: 100) : null,
                                                canOnlySwipeFromEdge: true,
                                                backGestureDetectionWidth: 45,
                                                builder: (context) {
                                                  return MultiBlocProvider(
                                                    providers: [
                                                      BlocProvider<CommunityBloc>.value(value: communityBloc),
                                                      BlocProvider<AccountBloc>.value(value: accountBloc),
                                                      BlocProvider<ThunderBloc>.value(value: thunderBloc)
                                                    ],
                                                    child: CreatePostPage(
                                                      communityId: widget.communityInfo!.communityView.community.id,
                                                      communityInfo: widget.communityInfo,
                                                      previousDraftPost: previousDraftPost,
                                                      onUpdateDraft: (p) => newDraftPost = p,
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                                .whenComplete(() async {
                                              timer.cancel();

                                              if (newDraftPost?.saveAsDraft == true && newDraftPost?.isNotEmpty == true) {
                                                await Future.delayed(const Duration(milliseconds: 300));
                                                showSnackbar(context, AppLocalizations.of(context)!.postSavedAsDraft);
                                                prefs.setString(draftId, jsonEncode(newDraftPost!.toJson()));
                                              } else {
                                                prefs.remove(draftId);
                                              }
                                            });
                                          }
                                        : null,
                                    style: TextButton.styleFrom(
                                      fixedSize: const Size.fromHeight(40),
                                      foregroundColor: null,
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.library_books_rounded,
                                          semanticLabel: 'New Post',
                                        ),
                                        SizedBox(width: 4.0),
                                        Text(
                                          'New Post',
                                          style: TextStyle(
                                            color: null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  width: 10,
                                  height: 8,
                                ),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: isUserLoggedIn
                                        ? () {
                                            HapticFeedback.mediumImpact();
                                            context.read<CommunityBloc>().add(
                                                  ChangeCommunitySubsciptionStatusEvent(
                                                    communityId: widget.communityInfo!.communityView.community.id,
                                                    follow: (widget.subscribedType == null) ? true : (widget.subscribedType == SubscribedType.notSubscribed ? true : false),
                                                  ),
                                                );
                                          }
                                        : null,
                                    style: TextButton.styleFrom(
                                      fixedSize: const Size.fromHeight(40),
                                      foregroundColor: null,
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          switch (widget.subscribedType) {
                                            SubscribedType.notSubscribed => Icons.add_circle_outline_rounded,
                                            SubscribedType.pending => Icons.pending_outlined,
                                            SubscribedType.subscribed => Icons.remove_circle_outline_rounded,
                                            _ => Icons.add_circle_outline_rounded,
                                          },
                                          semanticLabel: (widget.subscribedType == SubscribedType.notSubscribed || widget.subscribedType == null) ? 'Subscribe' : 'Unsubscribe',
                                        ),
                                        const SizedBox(width: 4.0),
                                        Text(
                                          switch (widget.subscribedType) {
                                            SubscribedType.notSubscribed => 'Subscribe',
                                            SubscribedType.pending => 'Pending...',
                                            SubscribedType.subscribed => 'Unsubscribe',
                                            _ => '',
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return SizeTransition(
                        sizeFactor: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: widget.subscribedType != SubscribedType.subscribed && widget.subscribedType != SubscribedType.pending
                        ? Padding(
                            padding: EdgeInsets.only(
                              top: isBlocked ? 10 : 4,
                              left: 12,
                              right: 12,
                              bottom: 4,
                            ),
                            child: ElevatedButton(
                              onPressed: isUserLoggedIn
                                  ? () {
                                      HapticFeedback.heavyImpact();
                                      hideSnackbar(context);
                                      context.read<CommunityBloc>().add(
                                            BlockCommunityEvent(
                                              communityId: widget.communityInfo!.communityView.community.id,
                                              block: isBlocked == true ? false : true,
                                            ),
                                          );
                                    }
                                  : null,
                              style: TextButton.styleFrom(
                                fixedSize: const Size.fromHeight(40),
                                foregroundColor: Colors.redAccent,
                                padding: EdgeInsets.zero,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isBlocked == true ? Icons.undo_rounded : Icons.block_rounded,
                                    semanticLabel: isBlocked == true ? 'Unblock Community' : 'Block Community',
                                  ),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    isBlocked == true ? 'Unblock Community' : 'Block Community',
                                  ),
                                ],
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10.0),
                  const Divider(
                    height: 0,
                    thickness: 2,
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 8.0,
                                  right: 8,
                                  bottom: 8,
                                ),
                                child: CommonMarkdownBody(
                                  body: widget.communityInfo?.communityView.community.description ?? '',
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 12.0, bottom: 6),
                                child: Row(children: [
                                  Text("Stats"),
                                  Expanded(
                                    child: Divider(
                                      height: 5,
                                      thickness: 2,
                                      indent: 15,
                                      endIndent: 5,
                                    ),
                                  ),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // TODO Make this use device date format
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.cake_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          'Created ${DateFormat.yMMMMd().format(widget.communityInfo!.communityView.community.published)} · ${formatTimeToString(dateTime: widget.communityInfo!.communityView.community.published.toIso8601String())} ago',
                                          style: TextStyle(color: theme.colorScheme.onBackground.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8.0),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.people_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.subscribers)} Subscribers',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.wysiwyg_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.posts)} Posts',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.chat_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.comments)} Comments',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8.0),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.calendar_month_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.usersActiveHalfYear)} users/6 mo',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.calendar_view_month_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.usersActiveMonth)} users/mo',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.calendar_view_week_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.usersActiveWeek)} users/wk',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                                          child: Icon(
                                            Icons.calendar_view_day_rounded,
                                            size: 18,
                                            color: theme.colorScheme.onBackground.withOpacity(0.65),
                                          ),
                                        ),
                                        Text(
                                          '${NumberFormat("#,###,###,###").format(widget.communityInfo?.communityView.counts.usersActiveDay)} users/day',
                                          style: TextStyle(color: theme.textTheme.titleSmall?.color?.withOpacity(0.65)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 16.0, bottom: 8),
                                child: Row(children: [
                                  Text("Moderators"),
                                  Expanded(
                                    child: Divider(
                                      height: 5,
                                      thickness: 2,
                                      indent: 15,
                                      endIndent: 5,
                                    ),
                                  ),
                                ]),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Column(
                                  children: [
                                    for (var mods in widget.communityInfo!.moderators)
                                      GestureDetector(
                                        onTap: () {
                                          navigateToUserPage(context, userId: mods.moderator!.id);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 8.0),
                                          child: Row(
                                            children: [
                                              UserAvatar(
                                                person: mods.moderator,
                                                radius: 20.0,
                                              ),
                                              const SizedBox(width: 16.0),
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      mods.moderator!.displayName ?? mods.moderator!.name,
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                    Text(
                                                      '${mods.moderator!.name} · ${fetchInstanceNameFromUrl(mods.moderator!.actorId)}',
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: theme.colorScheme.onBackground.withOpacity(0.6),
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                child: widget.communityInfo?.site != null
                                    ? Column(
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 12.0, bottom: 4),
                                            child: Row(children: [
                                              Text("Host Instance"),
                                              Expanded(
                                                child: Divider(
                                                  height: 5,
                                                  thickness: 2,
                                                  indent: 15,
                                                ),
                                              ),
                                            ]),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    CircleAvatar(
                                                      backgroundColor: widget.communityInfo?.site?.icon != null ? Colors.transparent : theme.colorScheme.secondaryContainer,
                                                      foregroundImage: widget.communityInfo?.site?.icon != null ? CachedNetworkImageProvider(widget.communityInfo!.site!.icon!) : null,
                                                      maxRadius: 24,
                                                      child: widget.communityInfo?.site?.icon == null
                                                          ? Text(
                                                              widget.communityInfo?.moderators.first.moderator!.name[0].toUpperCase() ?? '',
                                                              semanticsLabel: '',
                                                              style: const TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 16,
                                                              ),
                                                            )
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 16.0),
                                                    Expanded(
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            widget.communityInfo?.site?.name ?? /*widget.communityInfo?.instanceHost ??*/ '',
                                                            overflow: TextOverflow.ellipsis,
                                                            maxLines: 1,
                                                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                                                          ),
                                                          Text(
                                                            widget.communityInfo?.site?.description ?? '',
                                                            style: theme.textTheme.bodyMedium,
                                                            overflow: TextOverflow.visible,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const Divider(),
                                                CommonMarkdownBody(
                                                  body: widget.communityInfo?.site?.sidebar ?? '' /*?? widget.communityInfo?.instanceHost*/,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 128,
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
