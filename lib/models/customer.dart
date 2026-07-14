class Customer {
  final int? id;
  final String name;
  final String phone;
  final String createdAt;

  const Customer({
    this.id,
    required this.name,
    this.phone = '',
    this.createdAt = '',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'created_at': createdAt,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> m) {
    return Customer(
      id: m['id'] as int?,
      name: m['name'] as String,
      phone: (m['phone'] as String?) ?? '',
      createdAt: m['created_at'] as String? ?? '',
    );
  }
}