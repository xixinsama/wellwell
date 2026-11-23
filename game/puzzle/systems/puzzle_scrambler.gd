class_name PuzzleScrambler
extends RefCounted

## Random-walk scrambler for sliding-block puzzles.
##
## Every step is a turn produced by the puzzle's own rule set, including the
## void A+ induced moves, so a scrambled layout is always reachable from the
## start layout and therefore solvable. The walk only produces data: it never
## touches nodes, physics or the session history.

## Default number of random turns walked at load time.
const DEFAULT_STEPS := 120
## Extra turns allowed when the walk happens to return to the start layout.
const MAX_EXTRA_STEPS := 400


## Returns the scrambled layout, or null when the board has no legal turn to
## walk (for example a packed board, or void_only on a board without voids).
static func build_scrambled_state(
    definition: PuzzleDefinition,
    rules: PuzzleRuleSet,
    start_state: BoardState,
    steps: int,
    rng: RandomNumberGenerator,
    void_only: bool = true,
    avoid_reverse: bool = true
) -> BoardState:
    if definition == null or rules == null or start_state == null or rng == null:
        return null
    if definition.pieces.is_empty() or start_state.pieces.is_empty():
        return null
    var state := start_state.duplicate_state()
    var target_steps := maxi(1, steps)
    var step := 0
    var last_primary: PuzzleMove = null
    while step < target_steps or (
        step < target_steps + MAX_EXTRA_STEPS
        and state.get_hash_key() == start_state.get_hash_key()
    ):
        var turn := _pick_turn(definition, rules, state, rng, void_only, avoid_reverse, last_primary)
        if turn == null:
            return null if step == 0 else state
        for move: PuzzleMove in turn.moves:
            state = rules.apply_move(state, move)
        last_primary = turn.moves[0]
        step += 1
    return state


static func _pick_turn(
    definition: PuzzleDefinition,
    rules: PuzzleRuleSet,
    state: BoardState,
    rng: RandomNumberGenerator,
    void_only: bool,
    avoid_reverse: bool,
    last_primary: PuzzleMove
) -> PuzzleTurn:
    var candidates: Array[PuzzleTurn] = []
    var fallback: Array[PuzzleTurn] = []
    for move: PuzzleMove in rules.get_legal_moves(state):
        var turn := rules.resolve_turn(state, move)
        if turn == null or turn.is_empty():
            continue
        if void_only and not _turn_touches_void(definition, turn):
            continue
        fallback.append(turn)
        if avoid_reverse and _is_reverse_of(turn.moves[0], last_primary):
            continue
        candidates.append(turn)
    if candidates.is_empty():
        candidates = fallback
    if candidates.is_empty():
        return null
    return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _turn_touches_void(definition: PuzzleDefinition, turn: PuzzleTurn) -> bool:
    for move: PuzzleMove in turn.moves:
        if move.piece_index < 0 or move.piece_index >= definition.pieces.size():
            continue
        if definition.pieces[move.piece_index].is_void:
            return true
    return false


static func _is_reverse_of(move: PuzzleMove, previous: PuzzleMove) -> bool:
    if move == null or previous == null:
        return false
    return move.piece_index == previous.piece_index and move.get_direction() == -previous.get_direction()
