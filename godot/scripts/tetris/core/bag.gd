extends RefCounted
## 7-bag (random generator). Pure: no Engine, no global RNG.
##
## Each pull returns a piece kind from a freshly shuffled permutation of
## {I,O,T,S,Z,J,L}. After 7 pulls a new permutation is generated. Same seed
## always produces the same sequence. Use `peek(n)` for the Next preview.

const Self := preload("res://scripts/tetris/core/bag.gd")
const PieceKind := preload("res://scripts/tetris/core/piece_kind.gd")

var _rng: RandomNumberGenerator
var _bag: Array  # holds upcoming kinds in pull order; refilled when empty

static func create(bag_seed: int) -> Self:
	var b: Self = Self.new()
	b._init_seed(bag_seed)
	return b

func _init_seed(bag_seed: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = bag_seed
	_bag = []

func _refill() -> void:
	var arr: Array = PieceKind.KINDS.duplicate()
	# Fisher-Yates with seeded RNG.
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	_bag.append_array(arr)

## Returns the next piece kind, refilling the bag as needed.
func next() -> int:
	if _bag.is_empty():
		_refill()
	return _bag.pop_front()

## Look ahead at the next n piece kinds without consuming them.
func peek(n: int) -> Array:
	while _bag.size() < n:
		_refill()
	return _bag.slice(0, n)

## Reseed mid-stream. Existing pre-generated bag tail is *kept* (so the next
## few pulls match what was previewed); new pulls beyond that draw from the
## reseeded RNG. Call before a pull if you want full reproducibility.
func reseed(bag_seed: int) -> void:
	_rng.seed = bag_seed

## Drop any pre-generated bag content. Use together with reseed() if you want
## a fresh deterministic stream from this point on.
func reset_buffer() -> void:
	_bag.clear()
