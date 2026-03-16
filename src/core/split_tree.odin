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
split_tree_alloc :: proc(tree: ^SplitTree) -> int {
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
    idx := split_tree_alloc(tree)
    tree.nodes[idx] = SplitNode{parent = -1, variant = SplitLeaf{panel_id = panel_id}}
    tree.root = idx
}

// Returns true when the tree has no valid root (zero-initialised state).
split_tree_is_empty :: proc(tree: ^SplitTree) -> bool {
    return tree.nodes[tree.root].variant == nil
}

// Splits the leaf for current_panel_id, placing new_panel_id as the second
// child under a new inner node with the given direction.
split_tree_split :: proc(
    tree: ^SplitTree,
    current_panel_id: int,
    new_panel_id: int,
    dir: SplitDir,
) {
    leaf_idx := split_tree_find_leaf(tree, current_panel_id)
    if leaf_idx == -1 {return}

    old_parent := tree.nodes[leaf_idx].parent

    // Allocate the new panel's leaf
    new_leaf_idx := split_tree_alloc(tree)
    tree.nodes[new_leaf_idx] = SplitNode {
        parent  = -1, // patched below
        variant = SplitLeaf{panel_id = new_panel_id},
    }

    // Allocate the replacement inner node (takes the leaf's place in the tree)
    inner_idx := split_tree_alloc(tree)
    tree.nodes[inner_idx] = SplitNode {
        parent  = old_parent,
        variant = SplitInner{dir = dir, children = {leaf_idx, new_leaf_idx}},
    }

    // Patch child parent pointers
    tree.nodes[leaf_idx].parent    = inner_idx
    tree.nodes[new_leaf_idx].parent = inner_idx

    // Replace the old leaf reference in its parent (or root)
    if old_parent == -1 {
        tree.root = inner_idx
    } else {
        gp := &tree.nodes[old_parent].variant.(SplitInner)
        if gp.children[0] == leaf_idx {
            gp.children[0] = inner_idx
        } else {
            gp.children[1] = inner_idx
        }
    }
}

// Removes the leaf for panel_id and promotes its sibling up to fill the gap.
// Returns the panel_id of the surviving neighbour so the caller can refocus.
// Returns -1 if panel_id is the sole remaining leaf (cannot close the last one).
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

    grandparent_idx := tree.nodes[parent_idx].parent

    // Promote sibling to fill the parent's position
    tree.nodes[sibling_idx].parent = grandparent_idx
    if grandparent_idx == -1 {
        tree.root = sibling_idx
    } else {
        gp := &tree.nodes[grandparent_idx].variant.(SplitInner)
        if gp.children[0] == parent_idx {
            gp.children[0] = sibling_idx
        } else {
            gp.children[1] = sibling_idx
        }
    }

    split_tree_free(tree, leaf_idx)
    split_tree_free(tree, parent_idx)

    // Return the panel_id that should receive focus
    return split_tree_descend_first(tree, sibling_idx)
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
