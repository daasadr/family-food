import '../models/models.dart';
import 'api_client.dart';

/// Tenká typovaná vrstva nad ApiClientem — jedna metoda na endpoint.
class ApiService {
  ApiService(this._client);

  final ApiClient _client;

  // --- Auth -------------------------------------------------------------

  Future<({AppUser user, AuthTokens tokens})> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/auth/register',
      body: {'email': email, 'password': password, 'name': name},
      skipAuth: true,
    );
    return (
      user: AppUser.fromJson(data['user'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>),
    );
  }

  Future<({AppUser user, AuthTokens tokens})> login({
    required String email,
    required String password,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      body: {'email': email, 'password': password},
      skipAuth: true,
    );
    return (
      user: AppUser.fromJson(data['user'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>),
    );
  }

  Future<void> logout(String refreshToken) =>
      _client.post<void>('/auth/logout', body: {'refreshToken': refreshToken});

  /// Nevratné smazání účtu i souvisejících dat (GDPR).
  Future<void> deleteAccount() => _client.delete<void>('/auth/me');

  Future<AppUser> me() async {
    final data = await _client.get<Map<String, dynamic>>('/auth/me');
    return AppUser.fromJson(data);
  }

  // --- Rodina -----------------------------------------------------------

  Future<({Family family, AuthTokens tokens})> createFamily(String name) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/families',
      body: {'name': name},
    );
    return (
      family: Family.fromJson(data['family'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>),
    );
  }

  Future<Family> getFamily() async {
    final data = await _client.get<Map<String, dynamic>>('/families/me');
    return Family.fromJson(data);
  }

  Future<Family> updateFamily({String? name, List<int>? shoppingDays}) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/families/me',
      body: {
        if (name != null) 'name': name,
        if (shoppingDays != null) 'shoppingDays': shoppingDays,
      },
    );
    return Family.fromJson(data);
  }

  Future<AuthTokens> leaveFamily() async {
    final data = await _client.post<Map<String, dynamic>>('/families/me/leave');
    return AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>);
  }

  Future<Family> transferOwnership(String userId) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/families/me/transfer-ownership',
      body: {'userId': userId},
    );
    return Family.fromJson(data);
  }

  // --- Pozvánky ---------------------------------------------------------

  Future<Invite> createInvite({String? email}) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/families/me/invites',
      body: {if (email != null && email.isNotEmpty) 'email': email},
    );
    return Invite.fromJson(data);
  }

  Future<List<Invite>> listInvites() async {
    final data = await _client.get<List<dynamic>>('/families/me/invites');
    return data
        .map((e) => Invite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeInvite(String inviteId) =>
      _client.delete<void>('/families/me/invites/$inviteId');

  Future<({Family family, AuthTokens tokens})> acceptInvite(String code) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/families/invites/accept',
      body: {'code': code},
    );
    return (
      family: Family.fromJson(data['family'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>),
    );
  }

  // --- Šablona ----------------------------------------------------------

  Future<MealTemplate> getTemplate() async {
    final data = await _client.get<Map<String, dynamic>>('/planner/template');
    return MealTemplate.fromJson(data);
  }

  Future<MealTemplate> saveTemplate(List<TemplateSlot> slots) async {
    final data = await _client.put<Map<String, dynamic>>(
      '/planner/template',
      body: {'slots': slots.map((s) => s.toRequestJson()).toList()},
    );
    return MealTemplate.fromJson(data);
  }

  // --- Plánovač ---------------------------------------------------------

  Future<WeekPlan> getWeek(String startDate) async {
    final data = await _client.get<Map<String, dynamic>>(
      '/planner/week',
      query: {'start': startDate},
    );
    return WeekPlan.fromJson(data);
  }

  Future<DayPlan> getDay(String date) async {
    final data = await _client.get<Map<String, dynamic>>('/planner/days/$date');
    return DayPlan.fromJson(data);
  }

  Future<MealSlot> addCustomSlot({
    required String date,
    required String label,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/planner/days/$date/slots',
      body: {'slotType': 'custom', 'customLabel': label},
    );
    return MealSlot.fromJson(data);
  }

  Future<void> deleteSlot(String slotId) =>
      _client.delete<void>('/planner/slots/$slotId');

  // --- Návrhy -----------------------------------------------------------

  Future<MealProposal> createProposal({
    required String slotId,
    required String title,
    String? description,
    String? photoUrl,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/planner/slots/$slotId/proposals',
      body: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      },
    );
    return MealProposal.fromJson(data);
  }

  Future<MealProposal> getProposal(String id) async {
    final data =
        await _client.get<Map<String, dynamic>>('/planner/proposals/$id');
    return MealProposal.fromJson(data);
  }

  Future<MealProposal> updateProposal({
    required String id,
    String? title,
    String? description,
    String? photoUrl,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/planner/proposals/$id',
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (photoUrl != null) 'photoUrl': photoUrl,
      },
    );
    return MealProposal.fromJson(data);
  }

  Future<void> deleteProposal(String id) =>
      _client.delete<void>('/planner/proposals/$id');

  Future<MealProposal> confirmProposal(String id) async {
    final data = await _client
        .post<Map<String, dynamic>>('/planner/proposals/$id/confirm');
    return MealProposal.fromJson(data);
  }

  Future<MealProposal> unlockProposal(String id) async {
    final data = await _client
        .post<Map<String, dynamic>>('/planner/proposals/$id/unlock');
    return MealProposal.fromJson(data);
  }

  Future<MealProposal> vote(String id) async {
    final data =
        await _client.post<Map<String, dynamic>>('/planner/proposals/$id/vote');
    return MealProposal.fromJson(data);
  }

  Future<MealProposal> unvote(String id) async {
    final data = await _client
        .delete<Map<String, dynamic>>('/planner/proposals/$id/vote');
    return MealProposal.fromJson(data);
  }

  // --- Komentáře --------------------------------------------------------

  Future<List<MealComment>> listComments(String proposalId) async {
    final data = await _client
        .get<List<dynamic>>('/planner/proposals/$proposalId/comments');
    return data
        .map((e) => MealComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<MealComment> addComment({
    required String proposalId,
    required String text,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/planner/proposals/$proposalId/comments',
      body: {'text': text},
    );
    return MealComment.fromJson(data);
  }

  Future<void> deleteComment(String commentId) =>
      _client.delete<void>('/planner/comments/$commentId');

  // --- Nákupní seznam ---------------------------------------------------

  Future<ShoppingList> generateShoppingList({
    required String rangeStart,
    required String rangeEnd,
    bool includeProposed = false,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/shopping-lists/generate',
      body: {
        'rangeStart': rangeStart,
        'rangeEnd': rangeEnd,
        'includeProposed': includeProposed,
      },
    );
    return ShoppingList.fromJson(data);
  }

  Future<List<ShoppingListSummary>> shoppingLists() async {
    final data = await _client.get<List<dynamic>>('/shopping-lists');
    return data
        .map((e) => ShoppingListSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShoppingList> shoppingList(String id) async {
    final data = await _client.get<Map<String, dynamic>>('/shopping-lists/$id');
    return ShoppingList.fromJson(data);
  }

  Future<void> deleteShoppingList(String id) =>
      _client.delete<void>('/shopping-lists/$id');

  Future<ShoppingItem> addShoppingItem({
    required String listId,
    required String name,
    String? category,
    String? quantity,
    String? buyByDate,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/shopping-lists/$listId/items',
      body: {
        'name': name,
        if (category != null && category.isNotEmpty) 'category': category,
        if (quantity != null && quantity.isNotEmpty) 'quantity': quantity,
        if (buyByDate != null) 'buyByDate': buyByDate,
      },
    );
    return ShoppingItem.fromJson(data);
  }

  Future<ShoppingItem> updateShoppingItem({
    required String itemId,
    String? name,
    String? quantity,
    bool? isChecked,
  }) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '/shopping-lists/items/$itemId',
      body: {
        if (name != null) 'name': name,
        if (quantity != null) 'quantity': quantity,
        if (isChecked != null) 'isChecked': isChecked,
      },
    );
    return ShoppingItem.fromJson(data);
  }

  Future<void> deleteShoppingItem(String itemId) =>
      _client.delete<void>('/shopping-lists/items/$itemId');

  // --- Galerie ----------------------------------------------------------

  Future<List<GalleryItem>> gallery({String scope = 'all', String? search}) async {
    final data = await _client.get<List<dynamic>>(
      '/gallery',
      query: {
        'scope': scope,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return data
        .map((e) => GalleryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<GalleryItem> addGalleryItem({
    required String title,
    required String photoUrl,
    String? category,
  }) async {
    final data = await _client.post<Map<String, dynamic>>(
      '/gallery',
      body: {
        'title': title,
        'photoUrl': photoUrl,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    return GalleryItem.fromJson(data);
  }
}
