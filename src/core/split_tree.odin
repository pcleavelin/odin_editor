package core

SPLIT_TREE_MAX :: 64

SplitDir :: enum { Vertical, Horizontal }
// Vertical   = children side-by-side  (left | right)
// Horizontal = children stacked       (top  / bottom)

NavigateDir :: enum { Left, Right, Up, Down }

SplitLeaf :: struct {
    panel_id: int,
}

SplitInner :: struct {
    dir:      SplitDir,
    children: [2]int, // indices into SplitTree.nodes
}

// variant == nil means this slot is free
SplitNode :: struct {
    parent:  int, // index into nodes; -1 = root
    variant: union {SplitLeaf, SplitInner},
}

SplitTree :: struct {
    nodes: [SPLIT_TREE_MAX]SplitNode,
    root:  int, // index of root node
}

// Returns the index of the first free slot, or -1 if full.
split_tree_find_slot :: proc(tree: ^SplitTree) -> int {
    for i in 0 ..< SPLIT_TREE_MAX {
        if tree.nodes[i].variant == nil {
            return i
        }
    }
    return -1
}

// Frees a slot so it can be reused.
split_tree_free :: proc(tree: ^SplitTree, idx: int) {
    tree.nodes[idx] = {}
}

// Returns the index of the leaf whose panel_id matches, or -1.
split_tree_find_leaf :: proc(tree: ^SplitTree, panel_id: int) -> int {
    for i in 0 ..< SPLIT_TREE_MAX {
        if leaf, ok := tree.nodes[i].variant.(SplitLeaf); ok {
            if leaf.panel_id == panel_id {
                return i
            }
        }
    }
    return -1
}

// Initialises (or resets) the tree with a single leaf as the root.
split_tree_init :: proc(tree: ^SplitTree, panel_id: int) {
    for i in 0 ..< SPLIT_TREE_MAX {
        tree.nodes[i] = {}
    }
    idx := split_tree_find_slot(tree)
    tree.nodes[idx] = SplitNode{parent = -1, variant = SplitLeaf{panel_id = panel_id}}
    tree.root = idx
}

// Returns true when the tree has no valid root (zero-initialised state).
split_tree_is_empty :: proc(tree: ^SplitTree) -> bool {
    return tree.nodes[tree.root].variant == nil
}

// Splits the leaf for current_panel_id, placing new_panel_id as the second
// child. leaf_idx is promoted to an inner node in-place; two new leaves are
// allocated for the two panels. No grandparent update is needed.
split_tree_split :: proc(
    tree: ^SplitTree,
    current_panel_id: int,
    new_panel_id: int,
    dir: SplitDir,
) {
    leaf_idx := split_tree_find_leaf(tree, current_panel_id)
    if leaf_idx == -1 {return}

    // Allocate two new leaves; both point back to leaf_idx as parent
    leaf1_idx := split_tree_find_slot(tree)
    tree.nodes[leaf1_idx] = SplitNode {
        parent  = leaf_idx,
        variant = SplitLeaf{panel_id = current_panel_id},
    }

    leaf2_idx := split_tree_find_slot(tree)
    tree.nodes[leaf2_idx] = SplitNode {
        parent  = leaf_idx,
        variant = SplitLeaf{panel_id = new_panel_id},
    }

    // Promote leaf_idx to inner; its parent is already correct
    tree.nodes[leaf_idx].variant = SplitInner{dir = dir, children = {leaf1_idx, leaf2_idx}}
}

// Removes the leaf for panel_id by collapsing the sibling into the parent slot.
// The parent's own parent pointer is already correct, so no grandparent update
// is needed. Returns the panel_id that should receive focus, or -1 if this is
// the sole remaining leaf.
split_tree_close :: proc(tree: ^SplitTree, panel_id: int) -> int {
    leaf_idx := split_tree_find_leaf(tree, panel_id)
    if leaf_idx == -1 {return -1}

    parent_idx := tree.nodes[leaf_idx].parent
    if parent_idx == -1 {
        // Last panel — do not close
        return -1
    }

    inner       := tree.nodes[parent_idx].variant.(SplitInner)
    sibling_idx := inner.children[1] if inner.children[0] == leaf_idx else inner.children[0]

    // Copy sibling's content into the parent slot; parent's own parent is unchanged
    tree.nodes[parent_idx].variant = tree.nodes[sibling_idx].variant

    // If the sibling was an inner node, its children now point to sibling_idx —
    // redirect them to parent_idx
    if sibling_inner, ok := tree.nodes[parent_idx].variant.(SplitInner); ok {
        tree.nodes[sibling_inner.children[0]].parent = parent_idx
        tree.nodes[sibling_inner.children[1]].parent = parent_idx
    }

    split_tree_free(tree, leaf_idx)
    split_tree_free(tree, sibling_idx)

    return split_tree_descend_first(tree, parent_idx)
}

// Finds the adjacent panel in direction dir from current_panel_id.
// Returns its panel_id, or -1 if there is no neighbour in that direction.
split_tree_navigate :: proc(
    tree: ^SplitTree,
    current_panel_id: int,
    dir: NavigateDir,
) -> int {
    leaf_idx := split_tree_find_leaf(tree, current_panel_id)
    if leaf_idx == -1 {return -1}

    axis_is_vertical := dir == .Left || dir == .Right
    going_second     := dir == .Right || dir == .Down

    node_idx := leaf_idx
    for {
        parent_idx := tree.nodes[node_idx].parent
        if parent_idx == -1 {return -1}

        inner, ok := tree.nodes[parent_idx].variant.(SplitInner)
        if !ok {return -1}

        // Only act when the split direction matches the navigation axis
        inner_is_vertical := inner.dir == .Vertical
        if inner_is_vertical == axis_is_vertical {
            i_am_first := inner.children[0] == node_idx
            if going_second && i_am_first {
                return split_tree_descend_first(tree, inner.children[1])
            }
            if !going_second && !i_am_first {
                return split_tree_descend_last(tree, inner.children[0])
            }
        }

        node_idx = parent_idx
    }
}

// ── helpers ────────────────────────────────────────────────────────────────

// Descend into a subtree always taking the first child; returns the leaf's panel_id.
split_tree_descend_first :: proc(tree: ^SplitTree, idx: int) -> int {
    node_idx := idx
    for {
        switch v in tree.nodes[node_idx].variant {
        case SplitLeaf:
            return v.panel_id
        case SplitInner:
            node_idx = v.children[0]
        }
    }
}

// Descend into a subtree always taking the last child; returns the leaf's panel_id.
split_tree_descend_last :: proc(tree: ^SplitTree, idx: int) -> int {
    node_idx := idx
    for {
        switch v in tree.nodes[node_idx].variant {
        case SplitLeaf:
            return v.panel_id
        case SplitInner:
            node_idx = v.children[1]
        }
    }
}
