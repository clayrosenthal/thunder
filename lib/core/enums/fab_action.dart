import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lemmy_api_client/v3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swipeable_page_route/swipeable_page_route.dart';
import 'package:thunder/account/bloc/account_bloc.dart';
import 'package:thunder/community/bloc/community_bloc.dart';
import 'package:thunder/community/pages/community_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:thunder/community/pages/create_post_page.dart';
import 'package:thunder/core/auth/bloc/auth_bloc.dart';
import 'package:thunder/core/enums/local_settings.dart';
import 'package:thunder/core/models/post_view_media.dart';
import 'package:thunder/core/singletons/preferences.dart';
import 'package:thunder/post/bloc/post_bloc.dart';
import 'package:thunder/shared/snackbar.dart';
import 'package:thunder/thunder/bloc/thunder_bloc.dart';

enum FeedFabAction {
  openFab(),
  backToTop(),
  subscriptions(),
  changeSort(),
  refresh(),
  dismissRead(),
  newPost();

  bool isAllowed({CommunityState? state, CommunityPage? widget}) {
    switch (this) {
      case FeedFabAction.openFab:
        return true;
      case FeedFabAction.backToTop:
        return true;
      case FeedFabAction.subscriptions:
        return widget?.scaffoldKey != null;
      case FeedFabAction.changeSort:
        return true;
      case FeedFabAction.refresh:
        return true;
      case FeedFabAction.dismissRead:
        return true;
      case FeedFabAction.newPost:
        return state?.communityId != null || state?.communityName != null;
    }
  }

  IconData getIcon({IconData? override}) {
    if (override != null) {
      return override;
    }

    switch (this) {
      case FeedFabAction.openFab:
        return Icons.more_horiz_rounded;
      case FeedFabAction.backToTop:
        return Icons.arrow_upward;
      case FeedFabAction.subscriptions:
        return Icons.people_rounded;
      case FeedFabAction.changeSort:
        return Icons.sort_rounded;
      case FeedFabAction.refresh:
        return Icons.refresh_rounded;
      case FeedFabAction.dismissRead:
        return Icons.clear_all_rounded;
      case FeedFabAction.newPost:
        return Icons.add_rounded;
    }
  }

  String getTitle(BuildContext context) {
    switch (this) {
      case FeedFabAction.openFab:
        return AppLocalizations.of(context)!.open;
      case FeedFabAction.backToTop:
        return AppLocalizations.of(context)!.backToTop;
      case FeedFabAction.subscriptions:
        return AppLocalizations.of(context)!.subscriptions;
      case FeedFabAction.changeSort:
        return AppLocalizations.of(context)!.changeSort;
      case FeedFabAction.refresh:
        return AppLocalizations.of(context)!.refresh;
      case FeedFabAction.dismissRead:
        return AppLocalizations.of(context)!.dismissRead;
      case FeedFabAction.newPost:
        return AppLocalizations.of(context)!.createPost;
    }
  }

  void execute(BuildContext context, CommunityState state, {CommunityBloc? bloc, CommunityPage? widget, void Function()? override, SortType? sortType}) async {
    if (override != null) {
      override();
    }

    switch (this) {
      case FeedFabAction.openFab:
        context.read<ThunderBloc>().add(const OnFabToggle(true));
      case FeedFabAction.backToTop:
        context.read<ThunderBloc>().add(OnScrollToTopEvent());
      case FeedFabAction.subscriptions:
        widget?.scaffoldKey!.currentState!.openDrawer();
      case FeedFabAction.changeSort:
        // Invoked via override
        break;
      case FeedFabAction.refresh:
        context.read<AccountBloc>().add(GetAccountInformation());
        bloc?.add(
          GetCommunityPostsEvent(
            reset: true,
            sortType: sortType,
            communityId: state.communityId,
            listingType: state.listingType,
            communityName: state.communityName,
          ),
        );
      case FeedFabAction.dismissRead:
        context.read<ThunderBloc>().add(const OnDismissEvent(true));
      case FeedFabAction.newPost:
        if (bloc != null) {
          if (!context.read<AuthBloc>().state.isLoggedIn) {
            showSnackbar(context, AppLocalizations.of(context)!.mustBeLoggedInPost);
          } else {
            ThunderBloc thunderBloc = context.read<ThunderBloc>();
            AccountBloc accountBloc = context.read<AccountBloc>();

            final ThunderState thunderState = context.read<ThunderBloc>().state;
            final bool reduceAnimations = thunderState.reduceAnimations;

            SharedPreferences prefs = (await UserPreferences.instance).sharedPreferences;
            DraftPost? newDraftPost;
            DraftPost? previousDraftPost;
            String draftId = '${LocalSettings.draftsCache.name}-${state.communityId!}';
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
                      BlocProvider<CommunityBloc>.value(value: bloc),
                      BlocProvider<ThunderBloc>.value(value: thunderBloc),
                      BlocProvider<AccountBloc>.value(value: accountBloc),
                    ],
                    child: CreatePostPage(
                      communityId: state.communityId!,
                      communityInfo: state.communityInfo,
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
        }
    }
  }
}

enum PostFabAction {
  openFab(),
  backToTop(),
  changeSort(),
  replyToPost(),
  refresh();

  IconData getIcon({IconData? override, bool postLocked = false}) {
    if (override != null) {
      return override;
    }

    switch (this) {
      case PostFabAction.openFab:
        return Icons.more_horiz_rounded;
      case PostFabAction.backToTop:
        return Icons.arrow_upward;
      case PostFabAction.changeSort:
        return Icons.sort_rounded;
      case PostFabAction.replyToPost:
        if (postLocked) {
          return Icons.lock;
        }
        return Icons.reply_rounded;
      case PostFabAction.refresh:
        return Icons.refresh_rounded;
    }
  }

  String getTitle(BuildContext context, {bool postLocked = false}) {
    switch (this) {
      case PostFabAction.openFab:
        return AppLocalizations.of(context)!.open;
      case PostFabAction.backToTop:
        return AppLocalizations.of(context)!.backToTop;
      case PostFabAction.changeSort:
        return AppLocalizations.of(context)!.changeSort;
      case PostFabAction.replyToPost:
        if (postLocked) {
          return AppLocalizations.of(context)!.postLocked;
        }
        return AppLocalizations.of(context)!.replyToPost;
      case PostFabAction.refresh:
        return AppLocalizations.of(context)!.refresh;
    }
  }

  void execute({BuildContext? context, void Function()? override, PostViewMedia? postView, int? postId, int? selectedCommentId, String? selectedCommentPath}) {
    if (override != null) {
      override();
    }

    switch (this) {
      case PostFabAction.openFab:
        context?.read<ThunderBloc>().add(const OnFabToggle(true));
      case PostFabAction.backToTop:
        // Invoked via override
        break;
      case PostFabAction.changeSort:
        // Invoked via override
        break;
      case PostFabAction.replyToPost:
        // Invoked via override
        break;
      case PostFabAction.refresh:
        context?.read<PostBloc>().add(GetPostEvent(postView: postView, postId: postId, selectedCommentId: selectedCommentId, selectedCommentPath: selectedCommentPath));
    }
  }
}
