class UserModel {
  final int    id;
  final String name;
  final String email;
  final String token;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, String token) {
    return UserModel(
      id:    json['id']    as int,
      name:  json['name']  as String,
      email: json['email'] as String,
      token: token,
    );
  }
}