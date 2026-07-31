/// Datové modely odpovídající odpovědím backendového API.
/// Bez code-genu — ruční fromJson, ať je vidět, co přesně přichází.
library;

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.avatarUrl,
    this.familyId,
  });

  final String id;
  final String email;
  final String name;
  final String role;
  final String? avatarUrl;
  final String? familyId;

  bool get hasFamily => familyId != null;
  bool get isOwner => role == 'owner';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        familyId: json['familyId'] as String?,
      );
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? avatarUrl;

  bool get isOwner => role == 'owner';

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );
}

class Family {
  const Family({
    required this.id,
    required this.name,
    required this.subscriptionTier,
    required this.shoppingDays,
    required this.members,
  });

  final String id;
  final String name;
  final String subscriptionTier;
  final List<int> shoppingDays;
  final List<FamilyMember> members;

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as String,
        name: json['name'] as String,
        subscriptionTier: json['subscriptionTier'] as String,
        shoppingDays:
            (json['shoppingDays'] as List<dynamic>).map((e) => e as int).toList(),
        members: (json['members'] as List<dynamic>)
            .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Invite {
  const Invite({
    required this.id,
    required this.status,
    required this.expiresAt,
    this.email,
    this.code,
  });

  final String id;
  final String status;
  final DateTime expiresAt;
  final String? email;

  /// Vyplněné jen u právě vytvořené pozvánky — server ho vrací jednou.
  final String? code;

  factory Invite.fromJson(Map<String, dynamic> json) => Invite(
        id: json['id'] as String,
        status: json['status'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        email: json['email'] as String?,
        code: json['code'] as String?,
      );
}

enum SlotType { breakfast, snack1, lunch, snack2, dinner, custom }

SlotType slotTypeFromString(String value) => switch (value) {
      'breakfast' => SlotType.breakfast,
      'snack1' => SlotType.snack1,
      'lunch' => SlotType.lunch,
      'snack2' => SlotType.snack2,
      'dinner' => SlotType.dinner,
      _ => SlotType.custom,
    };

String slotTypeToString(SlotType type) => type.name;

/// Český název slotu pro UI.
String slotTypeLabel(SlotType type, {String? customLabel}) {
  if (customLabel != null && customLabel.isNotEmpty) return customLabel;
  return switch (type) {
    SlotType.breakfast => 'Snídaně',
    SlotType.snack1 => 'Dopolední svačina',
    SlotType.lunch => 'Oběd',
    SlotType.snack2 => 'Odpolední svačina',
    SlotType.dinner => 'Večeře',
    SlotType.custom => 'Vlastní jídlo',
  };
}

class TemplateSlot {
  const TemplateSlot({
    required this.id,
    required this.slotType,
    required this.enabled,
    required this.sortOrder,
    this.customLabel,
  });

  final String id;
  final SlotType slotType;
  final bool enabled;
  final int sortOrder;
  final String? customLabel;

  String get label => slotTypeLabel(slotType, customLabel: customLabel);

  TemplateSlot copyWith({bool? enabled, String? customLabel}) => TemplateSlot(
        id: id,
        slotType: slotType,
        enabled: enabled ?? this.enabled,
        sortOrder: sortOrder,
        customLabel: customLabel ?? this.customLabel,
      );

  factory TemplateSlot.fromJson(Map<String, dynamic> json) => TemplateSlot(
        id: json['id'] as String,
        slotType: slotTypeFromString(json['slotType'] as String),
        enabled: json['enabled'] as bool,
        sortOrder: json['sortOrder'] as int,
        customLabel: json['customLabel'] as String?,
      );

  Map<String, dynamic> toRequestJson() => {
        'slotType': slotTypeToString(slotType),
        'enabled': enabled,
        if (customLabel != null && customLabel!.isNotEmpty) 'customLabel': customLabel,
      };
}

class MealTemplate {
  const MealTemplate({required this.id, required this.slots});

  final String id;
  final List<TemplateSlot> slots;

  factory MealTemplate.fromJson(Map<String, dynamic> json) => MealTemplate(
        id: json['id'] as String,
        slots: (json['slots'] as List<dynamic>)
            .map((e) => TemplateSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProposalAuthor {
  const ProposalAuthor({required this.id, required this.name, this.avatarUrl});

  final String id;
  final String name;
  final String? avatarUrl;

  factory ProposalAuthor.fromJson(Map<String, dynamic> json) => ProposalAuthor(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );
}

enum ProposalStatus { proposed, confirmed, locked }

class MealProposal {
  const MealProposal({
    required this.id,
    required this.mealSlotId,
    required this.title,
    required this.status,
    required this.proposedBy,
    required this.voteCount,
    required this.votedByMe,
    required this.commentCount,
    this.description,
    this.photoUrl,
  });

  final String id;
  final String mealSlotId;
  final String title;
  final ProposalStatus status;
  final ProposalAuthor proposedBy;
  final int voteCount;
  final bool votedByMe;
  final int commentCount;
  final String? description;
  final String? photoUrl;

  bool get isConfirmed => status != ProposalStatus.proposed;

  factory MealProposal.fromJson(Map<String, dynamic> json) => MealProposal(
        id: json['id'] as String,
        mealSlotId: json['mealSlotId'] as String,
        title: json['title'] as String,
        status: switch (json['status'] as String) {
          'confirmed' => ProposalStatus.confirmed,
          'locked' => ProposalStatus.locked,
          _ => ProposalStatus.proposed,
        },
        proposedBy:
            ProposalAuthor.fromJson(json['proposedBy'] as Map<String, dynamic>),
        voteCount: json['voteCount'] as int,
        votedByMe: json['votedByMe'] as bool,
        commentCount: json['commentCount'] as int,
        description: json['description'] as String?,
        photoUrl: json['photoUrl'] as String?,
      );
}

class MealSlot {
  const MealSlot({
    required this.id,
    required this.slotType,
    required this.isCustomSlot,
    required this.sortOrder,
    required this.proposals,
    this.customLabel,
  });

  final String id;
  final SlotType slotType;
  final bool isCustomSlot;
  final int sortOrder;
  final List<MealProposal> proposals;
  final String? customLabel;

  String get label => slotTypeLabel(slotType, customLabel: customLabel);

  MealProposal? get confirmedProposal {
    for (final p in proposals) {
      if (p.isConfirmed) return p;
    }
    return null;
  }

  bool get isEmpty => proposals.isEmpty;

  factory MealSlot.fromJson(Map<String, dynamic> json) => MealSlot(
        id: json['id'] as String,
        slotType: slotTypeFromString(json['slotType'] as String),
        isCustomSlot: json['isCustomSlot'] as bool,
        sortOrder: json['sortOrder'] as int,
        customLabel: json['customLabel'] as String?,
        proposals: (json['proposals'] as List<dynamic>)
            .map((e) => MealProposal.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DayPlan {
  const DayPlan({required this.date, required this.slots});

  final String date;
  final List<MealSlot> slots;

  factory DayPlan.fromJson(Map<String, dynamic> json) => DayPlan(
        date: json['date'] as String,
        slots: (json['slots'] as List<dynamic>)
            .map((e) => MealSlot.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class DaySummary {
  const DaySummary({
    required this.date,
    required this.slotCount,
    required this.proposedCount,
    required this.confirmedCount,
  });

  final String date;
  final int slotCount;

  /// Počet slotů, kde je aspoň jeden návrh, ale nic potvrzeného.
  final int proposedCount;
  final int confirmedCount;

  int get emptyCount => slotCount - proposedCount - confirmedCount;
  bool get isFullyPlanned => slotCount > 0 && confirmedCount == slotCount;

  factory DaySummary.fromJson(Map<String, dynamic> json) => DaySummary(
        date: json['date'] as String,
        slotCount: json['slotCount'] as int,
        proposedCount: json['proposedCount'] as int,
        confirmedCount: json['confirmedCount'] as int,
      );
}

class WeekPlan {
  const WeekPlan({
    required this.weekStart,
    required this.weekEnd,
    required this.days,
  });

  final String weekStart;
  final String weekEnd;
  final List<DaySummary> days;

  factory WeekPlan.fromJson(Map<String, dynamic> json) => WeekPlan(
        weekStart: json['weekStart'] as String,
        weekEnd: json['weekEnd'] as String,
        days: (json['days'] as List<dynamic>)
            .map((e) => DaySummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class MealComment {
  const MealComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final ProposalAuthor author;

  factory MealComment.fromJson(Map<String, dynamic> json) => MealComment(
        id: json['id'] as String,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        author: ProposalAuthor.fromJson(json['author'] as Map<String, dynamic>),
      );
}

class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.title,
    required this.photoUrl,
    required this.isGlobal,
    this.category,
  });

  final String id;
  final String title;
  final String photoUrl;
  final bool isGlobal;
  final String? category;

  factory GalleryItem.fromJson(Map<String, dynamic> json) => GalleryItem(
        id: json['id'] as String,
        title: json['title'] as String,
        photoUrl: json['photoUrl'] as String,
        isGlobal: json['isGlobal'] as bool,
        category: json['category'] as String?,
      );
}
