// --- lib/models/coffee.dart ---

class Coffee {
  final String id;
  final String name;
  final String image;
  final double price;
  final String description;
  final String taste;
  final String suitable;

  Coffee({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.description,
    required this.taste,
    required this.suitable,
  });
}