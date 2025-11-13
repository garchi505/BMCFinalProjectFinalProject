import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CartItem {
  final String id;
  final String name;
  final double price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'quantity': quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    id: json['id'],
    name: json['name'],
    price: json['price'],
    quantity: json['quantity'],
  );
}

class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  List<CartItem> get items => [..._items];

  String? _userId;
  StreamSubscription? _authSubscription;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CartProvider() {
    print('CartProvider created.');
  }

  /// Initialize auth listener for user login/logout
  void initializeAuthListener() {
    print('CartProvider auth listener initialized');
    _authSubscription = _auth.authStateChanges().listen((User? user) async {
      if (user == null) {
        _userId = null;
        _items = []; // Clear cart on logout
      } else {
        _userId = user.uid;
        await _fetchCart(); // Load cart for logged-in user
      }
      notifyListeners();
    });
  }

  int get itemCount => _items.fold(0, (total, current) => total + current.quantity);
  double get subtotal => _items.fold(0.0, (total, current) => total + (current.price * current.quantity));
  double get vat => subtotal * 0.12;
  double get totalPriceWithVat => subtotal + vat;

  void addItem(String id, String name, double price, [int quantity = 1]) {
    var index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      _items[index].quantity += quantity;
    } else {
      _items.add(CartItem(id: id, name: name, price: price, quantity: quantity));
    }
    _saveCart();
    notifyListeners();
  }

  void increaseItemQuantity(String id) {
    var index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      _items[index].quantity++;
      _saveCart();
      notifyListeners();
    }
  }

  void decreaseItemQuantity(String id) {
    var index = _items.indexWhere((item) => item.id == id);
    if (index != -1) {
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        _items.removeAt(index);
      }
      _saveCart();
      notifyListeners();
    }
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    _saveCart();
    notifyListeners();
  }

  Future<void> placeOrder() async {
    if (_userId == null || _items.isEmpty) throw Exception('Cart is empty or user is not logged in.');

    try {
      final cartData = _items.map((item) => item.toJson()).toList();
      await _firestore.collection('orders').add({
        'userId': _userId,
        'items': cartData,
        'subtotal': subtotal,
        'vat': vat,
        'totalPrice': totalPriceWithVat,
        'itemCount': itemCount,
        'status': 'Pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearCart() async {
    _items = [];
    if (_userId != null) {
      try {
        await _firestore.collection('userCarts').doc(_userId).set({'cartItems': []});
      } catch (e) {
        print('Error clearing Firestore cart: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _fetchCart() async {
    if (_userId == null) {
      _items = [];
      notifyListeners();
      return;
    }

    try {
      final doc = await _firestore.collection('userCarts').doc(_userId).get();
      if (doc.exists && doc.data()!['cartItems'] != null) {
        final List<dynamic> cartData = doc.data()!['cartItems'];
        _items = cartData.map((item) => CartItem.fromJson(item)).toList();
      } else {
        _items = [];
      }
    } catch (e) {
      _items = [];
    }
    notifyListeners();
  }

  Future<void> _saveCart() async {
    if (_userId == null) return;

    try {
      final cartData = _items.map((item) => item.toJson()).toList();
      await _firestore.collection('userCarts').doc(_userId).set({'cartItems': cartData});
    } catch (e) {
      print('Error saving cart: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
