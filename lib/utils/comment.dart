import 'package:lemmy_api_client/v3.dart';
import 'package:thunder/account/models/account.dart';
import 'package:thunder/core/auth/helpers/fetch_account.dart';

import 'package:thunder/core/models/comment_view_tree.dart';
import 'package:thunder/core/singletons/lemmy_client.dart';

import 'date_time.dart';

// Optimistically updates a comment
CommentView optimisticallyVoteComment(CommentViewTree commentViewTree, VoteType voteType) {
  int newScore = commentViewTree.commentView!.counts.score;
  VoteType? existingVoteType = commentViewTree.commentView!.myVote;

  switch (voteType) {
    case VoteType.down:
      newScore--;
      break;
    case VoteType.up:
      newScore++;
      break;
    case VoteType.none:
      // Determine score from existing
      if (existingVoteType == VoteType.down) {
        newScore++;
      } else if (existingVoteType == VoteType.up) {
        newScore--;
      }
      break;
  }

  return commentViewTree.commentView!.copyWith(myVote: voteType, counts: commentViewTree.commentView!.counts.copyWith(score: newScore));
}

/// Logic to vote on a comment
Future<CommentView> voteComment(int commentId, VoteType score) async {
  Account? account = await fetchActiveProfileAccount();
  LemmyApiV3 lemmy = LemmyClient.instance.lemmyApiV3;

  if (account?.jwt == null) throw Exception('User not logged in');

  FullCommentView commentResponse = await lemmy.run(CreateCommentLike(
    auth: account!.jwt!,
    commentId: commentId,
    score: score,
  ));

  CommentView updatedCommentView = commentResponse.commentView;
  return updatedCommentView;
}

/// Logic to save a comment
Future<CommentView> saveComment(int commentId, bool save) async {
  Account? account = await fetchActiveProfileAccount();
  LemmyApiV3 lemmy = LemmyClient.instance.lemmyApiV3;

  if (account?.jwt == null) throw Exception('User not logged in');

  FullCommentView commentResponse = await lemmy.run(SaveComment(
    auth: account!.jwt!,
    commentId: commentId,
    save: save,
  ));

  CommentView updatedCommentView = commentResponse.commentView;
  return updatedCommentView;
}

/// Builds a tree of comments given a flattened list
List<CommentViewTree> buildCommentViewTree(List<CommentView> comments, {bool flatten = false}) {
  Map<String, CommentViewTree> commentMap = {};

  // Create a map of CommentView objects using the comment path as the key
  for (CommentView commentView in comments) {
    bool hasBeenEdited = commentView.comment.updated != null ? true : false;
    String commentTime = hasBeenEdited ? commentView.comment.updated!.toIso8601String() : commentView.comment.published.toIso8601String();

    commentMap[commentView.comment.path] = CommentViewTree(
      datePostedOrEdited: formatTimeToString(dateTime: commentTime),
      commentView: cleanDeletedCommentView(commentView),
      replies: [],
      level: commentView.comment.path.split('.').length - 2,
    );
  }

  if (flatten) {
    return commentMap.values.toList();
  }

  // Build the tree structure by assigning children to their parent comments
  for (CommentViewTree commentView in commentMap.values) {
    List<String> pathIds = commentView.commentView!.comment.path.split('.');
    String parentPath = pathIds.getRange(0, pathIds.length - 1).join('.');

    CommentViewTree? parentCommentView = commentMap[parentPath];

    if (parentCommentView != null) {
      parentCommentView.replies.add(commentView);
    }
  }

  // Return the root comments (those with an empty or "0" path)
  return commentMap.values.where((commentView) => commentView.commentView!.comment.path.isEmpty || commentView.commentView!.comment.path == '0.${commentView.commentView!.comment.id}').toList();
}

List<CommentViewTree> insertNewComment(List<CommentViewTree> comments, CommentView commentView) {
  List<String> parentIds = commentView.comment.path.split('.');
  String commentTime = commentView.comment.published.toIso8601String();

  CommentViewTree newCommentTree = CommentViewTree(
    datePostedOrEdited: formatTimeToString(dateTime: commentTime),
    commentView: commentView,
    replies: [],
    level: commentView.comment.path.split('.').length - 2,
  );

  if (parentIds[1] == commentView.comment.id.toString()) {
    comments.insert(0, newCommentTree);
    return comments;
  }

  String parentId = parentIds[parentIds.length - 2];
  CommentViewTree? parentComment = findParentComment(1, parentIds, parentId.toString(), comments);

  // TODO: surface some sort of error maybe if for some reason we fail to find parent comment
  if (parentComment != null) {
    parentComment.replies.insert(0, newCommentTree);
  }

  return comments;
}

CommentViewTree? findParentComment(int index, List<String> parentIds, String targetId, List<CommentViewTree> comments) {
  for (CommentViewTree existing in comments) {
    if (existing.commentView?.comment.id.toString() != parentIds[index]) {
      continue;
    }

    if (targetId == existing.commentView?.comment.id.toString()) {
      return existing;
    }

    return findParentComment(index + 1, parentIds, targetId, existing.replies);
  }

  return null;
}

List<int> findCommentIndexesFromCommentViewTree(List<CommentViewTree> commentTrees, int commentId, [List<int>? indexes]) {
  indexes ??= [];

  for (int i = 0; i < commentTrees.length; i++) {
    if (commentTrees[i].commentView!.comment.id == commentId) {
      return [...indexes, i]; // Return a copy of the indexes list with the current index added
    }

    indexes.add(i); // Add the current index to the indexes list

    List<int> foundIndexes = findCommentIndexesFromCommentViewTree(commentTrees[i].replies, commentId, indexes);

    if (foundIndexes.isNotEmpty) {
      return foundIndexes;
    }

    indexes.removeLast(); // Remove the last index when backtracking
  }

  return []; // Return an empty list if the target ID is not found
}

// Used for modifying the comment current comment tree so we don't have to refresh the whole thing
bool updateModifiedComment(List<CommentViewTree> commentTrees, FullCommentView moddedComment) {
  for (int i = 0; i < commentTrees.length; i++) {
    if (commentTrees[i].commentView!.comment.id == moddedComment.commentView.comment.id) {
      commentTrees[i].commentView = moddedComment.commentView;
      return true;
    }

    bool done = updateModifiedComment(commentTrees[i].replies, moddedComment);
    if (done) {
      return done;
    }
  }

  return false;
}

CommentView cleanDeletedCommentView(CommentView commentView) {
  if (!commentView.comment.deleted) {
    return commentView;
  }

  Comment deletedComment = convertToDeletedComment(commentView.comment);

  return CommentView(
      comment: deletedComment,
      creator: commentView.creator,
      post: commentView.post,
      community: commentView.community,
      counts: commentView.counts,
      creatorBannedFromCommunity: commentView.creatorBannedFromCommunity,
      saved: commentView.saved,
      creatorBlocked: commentView.creatorBlocked,
      instanceHost: commentView.instanceHost,
      commentReply: commentView.commentReply);
}

Comment convertToDeletedComment(Comment comment) {
  return Comment(
      id: comment.id,
      creatorId: comment.creatorId,
      postId: comment.postId,
      content: "_deleted by creator_",
      removed: comment.removed,
      distinguished: comment.distinguished,
      published: comment.published,
      deleted: comment.deleted,
      apId: comment.apId,
      local: comment.local,
      languageId: comment.languageId,
      instanceHost: comment.instanceHost,
      path: comment.path);
}
