class MobilePlaybackReplacementTransaction<T> {
  int _generation = 0;
  T? _active;
  T? _staged;
  bool _preparing = false;

  T? get active => _active;
  T? get staged => _staged;
  T? get visible => _active;
  bool get isStaging => _staged != null;
  bool get isPreparing => _preparing;
  bool get isRetaining => _preparing || _staged != null;
  int get generation => _generation;

  int reserve({required T active}) {
    _generation += 1;
    _active = active;
    _preparing = true;
    _staged = null;
    return _generation;
  }

  bool stagePrepared(int generation, T target) {
    if (generation != _generation || !_preparing || _staged != null) {
      return false;
    }
    _preparing = false;
    _staged = target;
    return true;
  }

  bool cancelPreparation(int generation) {
    if (generation != _generation || !_preparing || _staged != null) {
      return false;
    }
    _preparing = false;
    _active = null;
    return true;
  }

  int stage({required T active, required T target}) {
    final generation = reserve(active: active);
    stagePrepared(generation, target);
    return generation;
  }

  bool owns(int generation, T target) {
    return generation == _generation && identical(_staged, target);
  }

  bool retainsActive(T target) {
    return _staged != null && identical(_active, target);
  }

  bool quarantinesRetainedOwnerCallback({
    required Object callbackOwner,
    required Object? retainedOwner,
  }) {
    return isRetaining &&
        retainedOwner != null &&
        identical(callbackOwner, retainedOwner);
  }

  T? promote(int generation) {
    if (generation != _generation) return null;
    final target = _staged;
    if (target == null) return null;
    final retired = _active;
    _active = target;
    _staged = null;
    _preparing = false;
    return retired;
  }

  T? rollback(int generation) {
    if (generation != _generation) return null;
    final rejected = _staged;
    if (rejected == null) return null;
    _staged = null;
    _preparing = false;
    return rejected;
  }

  List<T> clear() {
    _generation += 1;
    final owned = <T>[];
    final staged = _staged;
    final active = _active;
    if (staged != null) owned.add(staged);
    if (active != null) owned.add(active);
    _staged = null;
    _active = null;
    _preparing = false;
    return owned;
  }
}
