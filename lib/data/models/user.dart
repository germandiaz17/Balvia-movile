/// Authenticated user, mirrors the backend's auth user DTO.
class User {
  const User({required this.id, required this.email, this.fullName});

  final String id;
  final String email;
  final String? fullName;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['full_name'] as String?,
  );
}
