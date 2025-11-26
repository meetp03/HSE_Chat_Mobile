// models/pagination_model.dart
class Pagination {
  final int? currentPage;
  final int? totalPages;
  final int? perPage;
  final int? totalRecords;
  final bool? hasNext;
  final bool? hasPrevious;
  final int? nextPage;
  final int? previousPage;

  Pagination({
      this.currentPage,
      this.totalPages,
      this.perPage,
      this.totalRecords,
      this.hasNext,
      this.hasPrevious,
    this.nextPage,
    this.previousPage,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      currentPage: json['current_page'] ?? json['currentPage'] ?? 1,
      totalPages: json['total_pages'] ?? json['totalPages'] ?? json['last_page'] ?? 1,
      perPage: json['per_page'] ?? json['per_page'] ?? 10,
      totalRecords: json['total_records'] ?? json['totalRecords'] ?? json['total'] ?? 0,
      hasNext: json['has_next'] ?? json['hasNext'] ?? false,
      hasPrevious: json['has_previous'] ?? json['hasPrevious'] ?? false,
      nextPage: json['next_page'] ?? json['nextPage'],
      previousPage: json['previous_page'] ?? json['previousPage'],
    );
  }
}